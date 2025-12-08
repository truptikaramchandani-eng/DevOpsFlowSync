// ======================================
// EXECUTE ANONYMOUS — FULL WORKING BLOCK
// ======================================

public class TempMetadataFetcher {

    // ----------------------------------------
    // Tooling Query Helper
    // ----------------------------------------
    public static Map<String,Object> queryTooling(String connId, String soql) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        // FIXED: remove semicolon, correct concatenation
        req.setEndpoint(
            System.Url.getOrgDomainUrl().toExternalForm() +
            '/services/data/v64.0/tooling/query/?q=' +
            EncodingUtil.urlEncode(soql, 'UTF-8')
        );

        HttpResponse res = http.send(req);
        System.debug('🔍 Tooling API Response: ' + res.getBody());

        Map<String, Object> parsed = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());

        if (parsed.containsKey('records') &&
            ((List<Object>)parsed.get('records')).size() > 0) {

            return (Map<String, Object>)
                   ((List<Object>)parsed.get('records'))[0];
        }

        return null;
    }

    // Convert generic metadata to XML
    public static String metadataToXml(String type, Map<String, Object> meta) {
        return '<' + type + '>' + JSON.serializePretty(meta) + '</' + type + '>';
    }

    // Convert Flow metadata to XML
    public static String convertFlowMetadataToXML(Map<String, Object> meta) {
        return '<Flow>' + JSON.serializePretty(meta) + '</Flow>';
    }

    // =====================================================
    // ⭐ MAIN METHOD: getProcessOrFlowMetadata
    // =====================================================
    public static String getProcessOrFlowMetadata(String connId, String processOrFlowName) {
        try {
            System.debug('Fetching metadata for: ' + processOrFlowName);

            String cleanName = processOrFlowName;
            if (cleanName.contains('__') && !cleanName.endsWith('__c')) {
                cleanName = cleanName.substringAfter('__');
            }

            // 1️⃣ Try FlowDefinition
            String flowDefSoql =
                'SELECT Id, Metadata, DeveloperName, NamespacePrefix ' +
                'FROM FlowDefinition WHERE DeveloperName = \'' +
                String.escapeSingleQuotes(cleanName) + '\'';

            Map<String, Object> flowDefResult = queryTooling(connId, flowDefSoql);

            if (flowDefResult != null && flowDefResult.containsKey('Metadata')) {
                Map<String, Object> meta = (Map<String, Object>) flowDefResult.get('Metadata');

                Map<String, Object> enhanced = new Map<String, Object>();
                enhanced.putAll(meta);
                enhanced.put('Type', 'Flow');
                enhanced.put('DeveloperName', flowDefResult.get('DeveloperName'));

                return metadataToXml('Flow', enhanced);
            }

            // 2️⃣ Try Flow (Process Builder)
            String flowSoql =
                'SELECT Id, Metadata, FullName, DeveloperName, ProcessType FROM Flow ' +
                'WHERE (ProcessType = \'Workflow\' OR ProcessType = \'AutoLaunchedFlow\') ' +
                'AND DeveloperName = \'' + String.escapeSingleQuotes(cleanName) + '\'';

            Map<String, Object> flowResult = queryTooling(connId, flowSoql);

            if (flowResult != null && flowResult.containsKey('Metadata')) {
                Map<String, Object> metadata = (Map<String, Object>) flowResult.get('Metadata');
                String pt = (String) flowResult.get('ProcessType');

                metadata.put('Type',
                    pt == 'Workflow' ? 'Process Builder' : 'AutoLaunched Flow'
                );

                return convertFlowMetadataToXML(metadata);
            }

            return '❌ Process Builder or Flow not found: ' + processOrFlowName;

        } catch (Exception e) {
            return '❌ ERROR fetching metadata: ' + e.getMessage();
        }
    }
}