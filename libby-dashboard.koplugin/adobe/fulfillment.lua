local fulfillment = {}

local DataStorage = require("datastorage")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local logger = require("logger")
local socket = require("socket")
local socketurl = require("socket.url")
local socketutil = require("socketutil")
local koutil = require("util")

local adobe = require("adobe.adobe")
local adobehash = require("adobe.util.adobehash")
local crypto = require("adobe.util.crypto")
local dom = require("adobe.util.dom")
local epub = require("adobe.epub")
local nativecrypto = require("adobe.util.nativecrypto")
local util = require("adobe.util.util")
local xml = require("adobe.util.xml")

local ADEPT = adobehash.ADEPT

local function uniqueCachePath(prefix, suffix)
    local cacheDir = DataStorage:getDataDir() .. "/cache/acsm.koplugin"
    if lfs.attributes(cacheDir, "mode") ~= "directory" then
        lfs.mkdir(cacheDir)
    end
    for i = 1, 999 do
        local path = cacheDir .. "/" .. prefix .. "-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)) .. suffix
        local f = io.open(path, "wx")
        if f then
            f:close()
            return path
        end
    end
    local fallback = cacheDir .. "/" .. prefix .. "-" .. tostring(os.time()) .. suffix
    local f = io.open(fallback, "w")
    if f then
        f:close()
    end
    return fallback
end

local TRANSIENT_HTTP_STATUS = {
    [502] = true,
    [503] = true,
    [504] = true,
}
local HTTP_MAX_ATTEMPTS = 3

local function requestToString(request, requestBody)
    request.headers = request.headers or {}
    request.headers["User-Agent"] = request.headers["User-Agent"] or socketutil.USER_AGENT

    local lastCode
    for attempt = 1, HTTP_MAX_ATTEMPTS do
        local sink, resp = socketutil.table_sink({})
        request.sink = sink
        if requestBody ~= nil then
            request.source = ltn12.source.string(requestBody)
        end

        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        local ok, code = pcall(function()
            return socket.skip(1, http.request(request))
        end)
        socketutil:reset_timeout()
        if not ok then
            return nil, code
        end

        local body = table.concat(resp)
        local numericCode = tonumber(code)
        lastCode = code
        if not TRANSIENT_HTTP_STATUS[numericCode] then
            if numericCode and (numericCode < 200 or numericCode >= 300) then
                logger.warn("[ACSM] HTTP request failed: status=", numericCode, "url=", tostring(request.url))
                return nil, "HTTP " .. tostring(numericCode)
            end
            if body == "" and not code then
                return nil, "request failed"
            end
            return body, code
        end

        logger.warn("[ACSM] transient HTTP failure: status=", numericCode, "attempt=", attempt, "url=", tostring(request.url))
        if attempt < HTTP_MAX_ATTEMPTS and type(socket.sleep) == "function" then
            socket.sleep(0.5 * attempt)
        end
    end

    return nil, "HTTP " .. tostring(lastCode) .. " after " .. tostring(HTTP_MAX_ATTEMPTS) .. " attempts"
end

local function adeptPost(endpoint, body)
    return requestToString({
        url = endpoint,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/vnd.adobe.adept+xml",
            ["Content-Length"] = tostring(#body),
        },
    }, body)
end

fulfillment._requestToString = requestToString

function fulfillment.fetchLicenseServiceCertificate(operatorURL, licenseURL)
    if not operatorURL or not licenseURL then
        return nil, "License service URL information is missing"
    end
    local endpoint = operatorURL:gsub("/+$", "") .. "/LicenseServiceInfo?licenseURL=" .. socketurl.escape(licenseURL)
    local response, code = requestToString({ url = endpoint, method = "GET" })
    if not response or tonumber(code) and (tonumber(code) < 200 or tonumber(code) >= 300) then
        return nil, "LicenseServiceInfo request failed: " .. tostring(code)
    end

    local parseOk, root = pcall(dom.parse, response)
    if not parseOk then
        return nil, "LicenseServiceInfo returned malformed XML: " .. tostring(root)
    end
    local nsMap = { adept = ADEPT, [""] = ADEPT }
    local certNode = dom.findDescendant(root, nsMap, "certificate", ADEPT)
    if not certNode then
        certNode = dom.findDescendant(root, nsMap, "certificate", nil)
    end
    local certificate = certNode and dom.textOf(certNode) or nil
    if not certificate or certificate == "" then
        return nil, "LicenseServiceInfo response did not contain a certificate"
    end
    return certificate
end

local function deserializeXml(body, context)
    local ok, parsed = pcall(xml.deserialize, body)
    if not ok then
        return nil, context .. " returned malformed XML: " .. tostring(parsed)
    end
    if type(parsed) ~= "table" then
        return nil, context .. " returned an invalid XML document"
    end
    return parsed
end

local function xmlError(parsed, fallback)
    local err = parsed and parsed.error
    if type(err) == "table" and err._attr and err._attr.data then
        return err._attr.data
    end
    if type(err) == "string" then
        return err
    end
    return fallback
end

local function collectNotifyUrls(node, nsMap, urls)
    urls = urls or {}
    for _, child in ipairs(node._children or {}) do
        if child._type == "ELEMENT" then
            local childNsMap = dom.nsMapFor(child, nsMap)
            local childNs, childName = dom.resolveNodeName(child, nsMap)
            if childNs == ADEPT and childName == "notify" then
                local notifyUrl = dom.childText(child, childNsMap, "notifyURL", ADEPT)
                if notifyUrl and notifyUrl ~= "" then
                    urls[#urls + 1] = notifyUrl
                end
            end
            collectNotifyUrls(child, childNsMap, urls)
        end
    end
    return urls
end

local adobeDigest = adobehash.digest

local function signXmlBody(xmlString, signingKey)
    local hashBytes, err = adobeDigest(xmlString)
    if not hashBytes then
        return nil, err
    end

    local signature, signErr = signingKey:sign_raw(hashBytes, nativecrypto.RSA_PKCS1_PADDING)
    if not signature then
        return nil, signErr
    end
    return util.base64.encode(signature)
end

function fulfillment.extractCertFromPKCS12(pkcs12B64, deviceKey)
    local pass = util.base64.encode(deviceKey.key)
    local decoded, err = nativecrypto.parse_pkcs12(util.base64.decode(pkcs12B64), pass)
    if err then
        return nil, err
    end
    return util.base64.encode(decoded.cert_der)
end

function fulfillment.operatorAuth(operatorURL, userUUID, userCert, licenseCert, authCert)
    local authURL = operatorURL:gsub("/Fulfill$", ""):gsub("/+$", "") .. "/Auth"
    local body = '<?xml version="1.0"?>\n'
    body = body .. '<adept:credentials xmlns:adept="' .. ADEPT .. '">\n'
    body = body .. "  <adept:user>" .. userUUID .. "</adept:user>\n"
    body = body .. "  <adept:certificate>" .. userCert .. "</adept:certificate>\n"
    body = body .. "  <adept:licenseCertificate>" .. licenseCert .. "</adept:licenseCertificate>\n"
    body = body .. "  <adept:authenticationCertificate>" .. authCert .. "</adept:authenticationCertificate>\n"
    body = body .. "</adept:credentials>"

    logger.info("[ACSM] Operator auth request")
    local resp, err = adeptPost(authURL, body)
    if not resp then
        return nil, "Operator auth failed: " .. tostring(err)
    end
    if resp == "" then
        return nil, "Operator auth failed: empty response"
    end
    local parsed, parseErr = deserializeXml(resp, "Operator auth")
    if not parsed then
        return nil, "Operator auth failed: " .. parseErr
    end
    if parsed.error then
        return nil, "Operator auth failed: " .. xmlError(parsed, resp)
    end
    if parsed.success == nil then
        return nil, "Operator auth failed: unexpected response"
    end
    return true
end

function fulfillment.initLicenseService(activationURL, operatorURL, userUUID, signingKey)
    local nonce, nonceErr = crypto.nonce()
    if not nonce then
        return nil, "InitLicenseService nonce failed: " .. tostring(nonceErr)
    end
    local expiration = util.expiration(10)

    local body = '<?xml version="1.0"?>\n'
    body = body .. '<adept:licenseServiceRequest xmlns:adept="' .. ADEPT .. '" identity="user">\n'
    body = body .. "  <adept:operatorURL>" .. dom.xmlEscape(operatorURL) .. "</adept:operatorURL>\n"
    body = body .. "  <adept:nonce>" .. nonce .. "</adept:nonce>\n"
    body = body .. "  <adept:expiration>" .. expiration .. "</adept:expiration>\n"
    body = body .. "  <adept:user>" .. userUUID .. "</adept:user>\n"
    local sig, sigErr = signXmlBody(body .. "</adept:licenseServiceRequest>", signingKey)
    if not sig then
        return nil, "InitLicenseService signing failed: " .. sigErr
    end
    body = body .. "  <adept:signature>" .. sig .. "</adept:signature>\n"
    body = body .. "</adept:licenseServiceRequest>"

    local initURL = activationURL:gsub("/+$", "") .. "/InitLicenseService"
    logger.info("[ACSM] InitLicenseService request")
    local resp, err = adeptPost(initURL, body)
    if not resp then
        return nil, "InitLicenseService failed: " .. tostring(err)
    end
    if resp == "" then
        return nil, "InitLicenseService failed: empty response"
    end
    local parsed, parseErr = deserializeXml(resp, "InitLicenseService")
    if not parsed then
        return nil, parseErr
    end
    if parsed.error then
        return nil, "InitLicenseService error: " .. xmlError(parsed, resp)
    end
    if parsed.success == nil then
        return nil, "InitLicenseService failed: unexpected response"
    end
    return true
end

function fulfillment.fulfill(acsmPath, userUUID, deviceUUID, fingerprint, signingKey)
    local acsmContent = koutil.readFromFile(acsmPath, "rb")
    if not acsmContent then
        return nil, "Cannot open ACSM file: " .. tostring(acsmPath)
    end

    local acsmParsed, parseErr = deserializeXml(acsmContent, "ACSM")
    if not acsmParsed then
        return nil, parseErr
    end
    local token = acsmParsed.fulfillmentToken
    if not token then
        return nil, "No fulfillmentToken in ACSM"
    end

    local operatorURL = token.operatorURL
    if type(operatorURL) == "table" then
        operatorURL = operatorURL[1]
    end
    if not operatorURL then
        return nil, "No operatorURL in ACSM"
    end

    local acsmXml = acsmContent:gsub("^<%?xml[^?]*%?>%s*", ""):gsub("%s+$", "")
    local body = '<?xml version="1.0"?>'
    body = body .. '<adept:fulfill xmlns:adept="' .. ADEPT .. '">'
    body = body .. "<adept:user>" .. userUUID .. "</adept:user>"
    body = body .. "<adept:device>" .. deviceUUID .. "</adept:device>"
    body = body .. "<adept:deviceType>standalone</adept:deviceType>"
    body = body .. acsmXml
    body = body .. "<adept:targetDevice>"
    body = body .. "<adept:softwareVersion>" .. adobe.VERSION.hobbes .. "</adept:softwareVersion>"
    body = body .. "<adept:clientOS>" .. adobe.VERSION.os .. "</adept:clientOS>"
    body = body .. "<adept:clientLocale>en</adept:clientLocale>"
    body = body .. "<adept:clientVersion>" .. adobe.VERSION.version .. "</adept:clientVersion>"
    body = body .. "<adept:deviceType>standalone</adept:deviceType>"
    body = body .. "<adept:productName>ADOBE Digitial Editions</adept:productName>"
    body = body .. "<adept:fingerprint>" .. fingerprint .. "</adept:fingerprint>"
    body = body .. "<adept:activationToken>"
    body = body .. "<adept:user>" .. userUUID .. "</adept:user>"
    body = body .. "<adept:device>" .. deviceUUID .. "</adept:device>"
    body = body .. "</adept:activationToken>"
    body = body .. "</adept:targetDevice>"
    body = body .. "</adept:fulfill>"

    local sig, sigErr = signXmlBody(body, signingKey)
    if not sig then
        return nil, "Fulfill signing failed: " .. sigErr
    end
    body = body:gsub("</adept:fulfill>$", "<adept:signature>" .. sig .. "</adept:signature></adept:fulfill>")

    local fulfillURL = operatorURL:gsub("/+$", "") .. "/Fulfill"
    logger.info("[ACSM] Fulfill request")

    local resp, code = adeptPost(fulfillURL, body)
    if not resp or resp == "" then
        return nil, "Fulfill request failed: " .. tostring(code)
    end

    local parsed, responseParseErr = deserializeXml(resp, "Fulfill")
    if not parsed then
        return nil, responseParseErr
    end
    if parsed.error then
        return nil, "Fulfill error: " .. xmlError(parsed, resp)
    end

    local root = dom.parse(resp)
    local rootNsMap = { adept = ADEPT, [""] = ADEPT }
    local fr, frNsMap = dom.findDescendant(root, rootNsMap, "fulfillmentResult", ADEPT)
    if not fr then
        return nil, "No fulfillmentResult in response"
    end
    local rii, riiNsMap = dom.firstElement(fr, frNsMap, "resourceItemInfo", ADEPT)
    if not rii then
        return nil, "No resourceItemInfo in response"
    end
    local licenseTokenNode, licenseTokenNsMap = dom.firstElement(rii, riiNsMap, "licenseToken", ADEPT)
    if not licenseTokenNode then
        return nil, "No licenseToken in response"
    end

    return {
        response = resp,
        operatorURL = operatorURL,
        src = dom.childText(rii, riiNsMap, "src", ADEPT),
        encryptedKey = dom.childText(licenseTokenNode, licenseTokenNsMap, "encryptedKey", ADEPT),
        keyType = dom.childText(licenseTokenNode, licenseTokenNsMap, "keyType", ADEPT),
        licenseURL = dom.childText(licenseTokenNode, licenseTokenNsMap, "licenseURL", ADEPT),
        licenseTokenXml = dom.serializeNode(licenseTokenNode),
        notifyURLs = collectNotifyUrls(fr, frNsMap, {}),
    }
end

function fulfillment.downloadBook(srcUrl, outputPath)
    local handle, err = io.open(outputPath, "wb")
    if not handle then
        return nil, err
    end

    local sink, sinkErr = socketutil.file_sink(handle)
    if not sink then
        return nil, sinkErr
    end

    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local ok, code = pcall(function()
        return socket.skip(
            1,
            http.request({
                url = srcUrl,
                sink = sink,
                headers = { ["User-Agent"] = socketutil.USER_AGENT },
            })
        )
    end)
    socketutil:reset_timeout()
    if not ok then
        return nil, code
    end

    local attr = lfs.attributes(outputPath)
    if not attr or attr.size == 0 then
        return nil, "Book download failed: " .. tostring(code)
    end
    return true
end

function fulfillment.decryptBookKey(encryptedKeyB64, licenseKey)
    if not encryptedKeyB64 then
        return nil, "Missing encryptedKey"
    end
    local decrypted, err = licenseKey.pkey:decrypt(util.base64.decode(encryptedKeyB64), nativecrypto.RSA_PKCS1_PADDING)
    if err then
        return nil, err
    end
    return decrypted
end

local function writeFile(path, contents)
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err
    end
    local ok, writeErr = file:write(contents)
    file:close()
    if not ok then
        return nil, writeErr
    end
    return true
end

local function protectedRightsXml(result)
    if not result or not result.licenseTokenXml then
        return nil, "Fulfillment response did not contain a license token"
    end
    if not result.licenseURL or result.licenseURL == "" then
        return nil, "License service URL is missing"
    end
    if not result.licenseServiceCertificate then
        return nil, "License service certificate is missing"
    end

    local newline = string.char(10)
    local parts = {
        '<?xml version="1.0"?>', newline,
        '<adept:rights xmlns:adept="' .. ADEPT .. '">', newline,
        result.licenseTokenXml, newline,
    }
    parts[#parts + 1] = '<adept:licenseServiceInfo><adept:licenseURL>'
    parts[#parts + 1] = dom.xmlEscape(result.licenseURL)
    parts[#parts + 1] = '</adept:licenseURL><adept:certificate>'
    parts[#parts + 1] = dom.xmlEscape(result.licenseServiceCertificate)
    parts[#parts + 1] = '</adept:certificate></adept:licenseServiceInfo>'
    parts[#parts + 1] = newline
    parts[#parts + 1] = '</adept:rights>'
    return table.concat(parts)
end

function fulfillment.saveProtectedEpub(inputPath, outputPath, result)
    local rightsXml, rightsErr = protectedRightsXml(result)
    if not rightsXml then
        return nil, rightsErr
    end

    local rightsPath = outputPath .. ".lic"
    local rightsOk, writeErr = writeFile(rightsPath, rightsXml)
    if not rightsOk then
        return nil, "Failed to write ADEPT rights sidecar: " .. tostring(writeErr)
    end

    local moved, moveErr = os.rename(inputPath, outputPath)
    if not moved then
        local copied, copyErr = koutil.copyFile(inputPath, outputPath)
        if not copied then
            os.remove(rightsPath)
            return nil, "Failed to preserve encrypted EPUB: " .. tostring(copyErr or moveErr)
        end
        os.remove(inputPath)
    end

    return {
        protected = true,
        rightsPath = rightsPath,
        response = result.response,
    }
end

function fulfillment.notify(notifyURL, userUUID, deviceUUID, signingKey)
    local nonce, nonceErr = crypto.nonce()
    if not nonce then
        return nil, nonceErr
    end
    local expiration = util.expiration(10)

    local body = '<?xml version="1.0"?>\n'
    body = body .. '<adept:notification xmlns:adept="' .. ADEPT .. '">\n'
    body = body .. "  <adept:user>" .. userUUID .. "</adept:user>\n"
    body = body .. "  <adept:device>" .. deviceUUID .. "</adept:device>\n"
    body = body .. "  <adept:nonce>" .. nonce .. "</adept:nonce>\n"
    body = body .. "  <adept:expiration>" .. expiration .. "</adept:expiration>\n"
    local sig, sigErr = signXmlBody(body .. "</adept:notification>", signingKey)
    if not sig then
        return nil, sigErr
    end
    body = body .. "  <adept:signature>" .. sig .. "</adept:signature>\n"
    body = body .. "</adept:notification>"

    logger.info("[ACSM] Notify request")
    local response, err = adeptPost(notifyURL, body)
    if not response then
        return nil, err
    end
    return true
end

function fulfillment.process(acsmPath, outputPath, creds, deviceUUID, fingerprint, authCert, options)
    options = options or {}
    outputPath = outputPath or acsmPath:gsub("%.acsm$", ".epub")
    logger.info("[ACSM] fulfillment.process: acsmPath=", acsmPath, "outputPath=", outputPath)

    local userUUID = creds.user
    if type(userUUID) == "table" then
        userUUID = userUUID[1]
    end

    logger.info("[ACSM] fulfillment.process: extracting user cert from PKCS12...")
    local userCert, certErr = fulfillment.extractCertFromPKCS12(creds.pkcs12, creds.deviceKey)
    if not userCert then
        return nil, "Failed to extract cert: " .. certErr
    end
    logger.info("[ACSM] fulfillment.process: got user cert")

    logger.info("[ACSM] fulfillment.process: reading ACSM file...")
    local acsmContent = koutil.readFromFile(acsmPath, "rb")
    if not acsmContent then
        return nil, "Cannot open ACSM file: " .. tostring(acsmPath)
    end
    local acsmParsed, acsmParseErr = deserializeXml(acsmContent, "ACSM")
    if not acsmParsed then
        return nil, acsmParseErr
    end
    local token = acsmParsed.fulfillmentToken
    if type(token) ~= "table" then
        return nil, "No fulfillmentToken in ACSM"
    end
    local operatorURL = token.operatorURL
    if type(operatorURL) == "table" then
        operatorURL = operatorURL[1]
    end
    if not operatorURL then
        return nil, "No operatorURL in ACSM"
    end
    logger.info("[ACSM] fulfillment.process: operator URL available")

    logger.info("[ACSM] fulfillment.process: decoding pkcs12...")
    local pkcs12Key, pkcs12Err = crypto.decodepkcs12(creds.pkcs12, creds.deviceKey)
    if not pkcs12Key then
        return nil, "Failed to decode PKCS12: " .. tostring(pkcs12Err)
    end
    local activationURL = creds.activationURL or "https://adeactivate.adobe.com/adept"
    if not creds.activationURL and creds.activationXml then
        local activationParsed, activationParseErr = deserializeXml(creds.activationXml, "Saved activation")
        if not activationParsed then
            return nil, activationParseErr
        end
        local activationToken = activationParsed.activationInfo and activationParsed.activationInfo.activationToken
            or activationParsed.activationToken
        if activationToken and activationToken.activationURL then
            activationURL = activationToken.activationURL
            if type(activationURL) == "table" then
                activationURL = activationURL[1]
            end
        end
    end

    logger.info("[ACSM] fulfillment.process: doing operator auth...")
    local ok, err = fulfillment.operatorAuth(operatorURL, userUUID, userCert, creds.licenseCert, authCert)
    if not ok then
        return nil, err
    end
    logger.info("[ACSM] fulfillment.process: operator auth done, init license service...")

    ok, err = fulfillment.initLicenseService(activationURL, operatorURL, userUUID, pkcs12Key)
    if not ok then
        return nil, err
    end
    logger.info("[ACSM] fulfillment.process: license service initialized, fulfilling...")

    local result
    result, err = fulfillment.fulfill(acsmPath, userUUID, deviceUUID, fingerprint, pkcs12Key)
    if err and err:find("E_ADEPT_DISTRIBUTOR_AUTH") then
        logger.info("[ACSM] fulfillment.process: got DISTRIBUTOR_AUTH error, retrying operator auth...")
        local authOk, authErr = fulfillment.operatorAuth(operatorURL, userUUID, userCert, creds.licenseCert, authCert)
        if not authOk then
            return nil, authErr
        end
        result, err = fulfillment.fulfill(acsmPath, userUUID, deviceUUID, fingerprint, pkcs12Key)
    end
    if err then
        return nil, err
    end
    logger.info("[ACSM] fulfillment.process: fulfillment returned a download URL")

    -- Download the book (detect format from magic bytes)
    local tmpFile = uniqueCachePath("fulfillment", ".bin")
    logger.info("[ACSM] fulfillment.process: downloading book to", tmpFile)
    local _, downloadErr = fulfillment.downloadBook(result.src, tmpFile)
    if downloadErr then
        os.remove(tmpFile)
        return nil, downloadErr
    end
    logger.info("[ACSM] fulfillment.process: download complete")

    -- Detect format from magic bytes
    local magicF = io.open(tmpFile, "rb")
    local magic = magicF and magicF:read(10) or ""
    if magicF then
        magicF:close()
    end

    local isPdf = (magic:sub(1, 5) == "%PDF-")
    local isEpub = (magic:sub(1, 4) == "PK" .. string.char(0x03, 0x04))

    logger.info("[ACSM] fulfillment.process: format detected: ", isPdf and "PDF" or (isEpub and "EPUB" or "unknown"))

    if type(options.resolve_output_path) == "function" then
        local resolvedPath, resolveErr = options.resolve_output_path(tmpFile, {
            is_epub = isEpub,
            is_pdf = isPdf,
            extension = isPdf and "pdf" or (isEpub and "epub" or nil),
        })
        if not resolvedPath then
            os.remove(tmpFile)
            return nil, "Could not resolve book destination: " .. tostring(resolveErr or "unknown error")
        end
        outputPath = resolvedPath
        logger.info("[ACSM] fulfillment.process: resolved outputPath=", outputPath)
    end

    local preparedInfo, prepareErr
    local bookKey -- may be nil for PDF or protected EPUB
    local protectedMode = options.protected_epub == true and isEpub
    if isPdf then
        logger.info("[ACSM] fulfillment.process: decrypting PDF...")
        local pdf = require("adobe.pdf")
        -- PDF path: let decryptAdobePdf extract the book key from the PDF's
        -- ADEPT_LICENSE, handling hardening removal automatically.
        -- Pass fulfillment encrypted key as fallback for older ADEPT schemes
        -- that don't embed ADEPT_LICENSE in the PDF.
        preparedInfo, prepareErr = pdf.decryptAdobePdf(tmpFile, outputPath, nil, creds.licenseKey, result.encryptedKey)
    elseif protectedMode then
        logger.info("[ACSM] fulfillment.process: fetching license service certificate...")
        local licenseCertificate, certErr = fulfillment.fetchLicenseServiceCertificate(result.operatorURL, result.licenseURL)
        if not licenseCertificate then
            os.remove(tmpFile)
            return nil, certErr
        end
        result.licenseServiceCertificate = licenseCertificate
        logger.info("[ACSM] fulfillment.process: preserving encrypted EPUB with ADEPT rights sidecar...")
        preparedInfo, prepareErr = fulfillment.saveProtectedEpub(tmpFile, outputPath, result)
        if preparedInfo then
            tmpFile = nil -- saveProtectedEpub moved or copied the encrypted payload into place
        end
    else
        logger.info("[ACSM] fulfillment.process: decrypting book key...")
        local bookKeyErr
        bookKey, bookKeyErr = fulfillment.decryptBookKey(result.encryptedKey, creds.licenseKey)
        if not bookKey then
            os.remove(tmpFile)
            return nil, "Failed to decrypt book key: " .. bookKeyErr
        end
        logger.info("[ACSM] fulfillment.process: book key decrypted")

        logger.info("[ACSM] fulfillment.process: decrypting EPUB...")
        preparedInfo, prepareErr = epub.decryptAdobeEpub(tmpFile, outputPath, bookKey)
    end

    if tmpFile then
        os.remove(tmpFile)
    end
    if not preparedInfo then
        local action = protectedMode and "preserve protected EPUB" or (isPdf and "decrypt PDF" or "decrypt EPUB")
        return nil, "Failed to " .. action .. ": " .. tostring(prepareErr)
    end
    logger.info("[ACSM] fulfillment.process: book prepared at", outputPath)
    if result.notifyURLs and #result.notifyURLs > 0 then
        for _, notifyURL in ipairs(result.notifyURLs) do
            fulfillment.notify(notifyURL, userUUID, deviceUUID, pkcs12Key)
        end
    end

    return {
        outputPath = outputPath,
        bookKey = bookKey,
        protected = preparedInfo.protected == true,
        rightsPath = preparedInfo.rightsPath,
        decryptedEntries = preparedInfo.decryptedEntries or preparedInfo.decryptedObjects,
        remainingEncryptionXml = preparedInfo.remainingEncryptionXml,
        response = result.response,
    }
end

-- Export internal functions for testing (underscore-prefixed = internal API)
fulfillment._protectedRightsXml = protectedRightsXml
fulfillment._collectNotifyUrls = collectNotifyUrls
fulfillment._signXmlBody = signXmlBody

return fulfillment
