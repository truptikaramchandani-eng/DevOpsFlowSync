public with sharing class MetadataFetcher {

    // =====================================================================================
    // MAIN ENTRY (run from Anonymous Apex)
    // =====================================================================================
    public static void fetchAllObjectMetadata() {

        System.debug('🚀 START Metadata Fetching');

        Map<String, Schema.SObjectType> allObjects = Schema.getGlobalDescribe();

        Integer calloutCount = 0;
        Integer maxCallouts = 95; // safe buffer

        for (String objName : allObjects.keySet()) {

            // Skip unsupported object types
            if (shouldSkipObject(objName)) {
                System.debug('⏩ SKIPPED: ' + objName);
                continue;
            }

            // avoid callout limit
            if (calloutCount >= maxCallouts) {
                System.debug('⚠️ STOPPED: Approaching callout limit. Processed: ' + calloutCount);
                break;
            }

            String xml = fetchObjectMetadata(objName);

            if (xml != null) {
                System.debug('📄 XML for ' + objName + ':\n' + xml);
            }

            calloutCount++;
        }

        System.debug('✅ COMPLETED. Total processed: ' + calloutCount);
    }

    // =====================================================================================
    // OBJECT SKIP LOGIC
    // =====================================================================================
    private static Boolean shouldSkipObject(String objName) {

        // These do NOT have CustomObject metadata
        if (
            objName.endsWith('History') ||
            objName.endsWith('ChangeEvent') ||
            objName.endsWith('Feed') ||
            objName.endsWith('Share') ||
            objName.endsWith('Tag') ||
            objName.contains('Relation') ||
            objName.contains('Event') ||
            objName.contains('Feed') ||
            objName.contains('Tag') ||
            objName.contains('Share') ||
            objName.startsWith('AuthorizationForm') ||
            objName.contains('Aura') ||
            objName.contains('Apex') ||
            objName.contains('Login') ||
            objName.contains('RecordType')
        ) {
            return true;
        }

        return false;
    }

    // =====================================================================================
    // FETCH METADATA FROM TOOLING API
    // =====================================================================================
    private static String fetchObjectMetadata(String objectName) {

        try {

            String sessionId = UserInfo.getSessionId();
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();

            String encoded = EncodingUtil.urlEncode(objectName, 'UTF-8');

            String url = baseUrl + '/services/data/v57.0/tooling/sobjects/CustomObject/' + encoded;

            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(url);
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            req.setHeader('Content-Type', 'application/json');

            Http http = new Http();
            HTTPResponse res = http.send(req);

            // Skip objects with no metadata
            if (res.getStatusCode() == 404 || res.getBody().contains('NOT_FOUND')) {
                System.debug('⏩ Not a CustomObject metadata type: ' + objectName);
                return null;
            }

            Map<String, Object> jsonMap =
                (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            return convertToXml(jsonMap);
        }
        catch (Exception e) {
            System.debug('❌ ERROR for ' + objectName + ': ' + e.getMessage());
            return null;
        }
    }

    // =====================================================================================
    // JSON → XML converter (NO STRINGBUILDER)
    // =====================================================================================
    private static String convertToXml(Map<String, Object> data) {

        String xml = '';
        xml += '<?xml version="1.0" encoding="UTF-8"?>\n';
        xml += '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n';

        for (String key : data.keySet()) {

            Object val = data.get(key);
            if (val == null) continue;

            // LIST values
            if (val instanceof List<Object>) {

                List<Object> listVal = (List<Object>) val;

                for (Object row : listVal) {

                    if (row instanceof Map<String, Object>) {

                        xml += '    <' + key + '>\n';

                        Map<String, Object> rowMap = (Map<String, Object>) row;

                        for (String subKey : rowMap.keySet()) {
                            xml += '        <' + subKey + '>' +
                                   rowMap.get(subKey) +
                                   '</' + subKey + '>\n';
                        }

                        xml += '    </' + key + '>\n';
                    }
                }
            }

            // Single values (string, int, boolean)
            if (
                val instanceof String ||
                val instanceof Boolean ||
                val instanceof Integer
            ) {
                xml += '    <' + key + '>' + val + '</' + key + '>\n';
            }
        }

        xml += '</CustomObject>';

        return xml;
    }
}