public class MetadataExporter {
    
    // Main method to export custom metadata to multiple XML files
    public static Map<String, String> exportCustomMetadataToFiles(String nc, String customMetadataTypeName) {
        Map<String, String> filesMap = new Map<String, String>();
        
        try {
            Http http = new Http();
            String apiVersion = 'v61.0';
            
            // Determine API name
            String apiName = customMetadataTypeName.endsWith('__mdt') ? 
                customMetadataTypeName : customMetadataTypeName + '__mdt';
            String displayName = apiName.replace('__mdt', '');
            String name = displayName;
            String noNamespace = name.contains('__')
                ? name.substringAfter('__')
                : name;
            
            // Get type definition
            String typeQuery = 'SELECT Id, DeveloperName, NamespacePrefix ' +
                'FROM CustomObject ' +
                'WHERE DeveloperName = \'' + String.escapeSingleQuotes(noNamespace) + '\'';
            
            String typeEndpoint = 'callout:' + nc + '/services/data/' + apiVersion + '/tooling/query/?q=' + 
                EncodingUtil.urlEncode(typeQuery, 'UTF-8');
            
            HttpRequest typeReq = new HttpRequest();
            typeReq.setEndpoint(typeEndpoint);
            typeReq.setMethod('GET');
            typeReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse typeRes = http.send(typeReq);
            
            if (typeRes.getStatusCode() != 200) {
                filesMap.put('ERROR', 'Error getting type: ' + typeRes.getStatusCode() + ' - ' + typeRes.getBody());
                return filesMap;
            }
            
            Map<String, Object> typeResult = (Map<String, Object>) JSON.deserializeUntyped(typeRes.getBody());
            List<Object> typeRecords = (List<Object>) typeResult.get('records');
            
            if (typeRecords.isEmpty()) {
                filesMap.put('ERROR', 'Error: Custom metadata type not found');
                return filesMap;
            }
            
            Map<String, Object> typeRecord = (Map<String, Object>) typeRecords[0];
            String typeId = (String) typeRecord.get('Id');
            String namespacePrefix = (String) typeRecord.get('NamespacePrefix');
            
            // Get all custom field definitions with their data types
            Map<String, String> fieldTypeMap = getFieldTypeMap(nc, apiVersion, typeId);
            
            // Find all record IDs for this custom metadata type
            List<String> recordIds = findAllRecordIds(nc, customMetadataTypeName);
            
            // Get all field definitions for field names
            List<Map<String, Object>> customFields = getCustomFieldDefinitions(nc, apiVersion, typeId);
            
            // Process each record individually
            Integer recordCount = 0;
            for (String recordId : recordIds) {
                recordCount++;
                
                // Get field values for this specific record
                Map<String, Object> recordValues = getRecordFieldValues(
                    nc, apiVersion, recordId, customFields, customMetadataTypeName
                );
                
                if (recordValues.containsKey('DeveloperName')) {
                    String recordDeveloperName = (String) recordValues.get('DeveloperName');
                    
                    // Generate XML for this single record
                    String xmlContent = generateSingleRecordXml(
                        recordDeveloperName, 
                        recordValues, 
                        fieldTypeMap
                    );
                    
                    // Create filename in the correct format
                    // Example: Jira_Configuration.API_Config.md-meta.xml
                    String fileName = recordDeveloperName + '.md-meta.xml';
                    
                    // Create the full path for Git/VS Code structure
                    // force-app/main/default/customMetadata/Jira_Configuration.API_Config.md-meta.xml
                    String filePath = 'force-app/main/default/customMetadata/' + fileName;
                    
                    filesMap.put(filePath, xmlContent);
                    System.debug('Generated file: ' + filePath);
                }
            }
            
            System.debug('Total records processed: ' + recordCount);
            System.debug('Total files generated: ' + filesMap.size());
            
            return filesMap;
            
        } catch (Exception e) {
            System.debug('Export failed: ' + e.getMessage() + ' at line ' + e.getLineNumber());
            filesMap.put('ERROR', 'Export failed: ' + e.getMessage());
            return filesMap;
        }
    }
    
    // Generate XML for a single custom metadata record
    private static String generateSingleRecordXml(
        String developerName, 
        Map<String, Object> fieldValues, 
        Map<String, String> fieldTypeMap
    ) {
        List<String> xmlLines = new List<String>();
        
        xmlLines.add('<?xml version="1.0" encoding="UTF-8"?>');
        xmlLines.add('<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" ' +
                     'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                     'xmlns:xsd="http://www.w3.org/2001/XMLSchema">');
        
        // Extract label from DeveloperName (part after dot, or full name if no dot)
        String label = developerName.contains('.') 
            ? developerName.substringAfter('.') 
            : developerName;
        xmlLines.add('    <label>' + escapeXml(label) + '</label>');
        xmlLines.add('    <protected>false</protected>');
        
        // Process all fields except DeveloperName
        List<String> sortedFieldNames = new List<String>(fieldValues.keySet());
        sortedFieldNames.sort();
        
        for (String fieldName : sortedFieldNames) {
            if (fieldName != 'DeveloperName') {
                Object value = fieldValues.get(fieldName);
                
                if (value != null) {
                    xmlLines.add('    <values>');
                    xmlLines.add('        <field>' + escapeXml(fieldName) + '</field>');
                    
                    String stringValue = String.valueOf(value);
                    
                    // Extract clean field name without namespace and suffix
                    String cleanFieldName = fieldName.replaceAll('^[a-zA-Z0-9]+__', '').replaceAll('(__c|__mdt|__r)$', '');
                    String dataType = fieldTypeMap.get(cleanFieldName);
                    String xsiType = determineXsiTypeFromDataType(dataType);
                    String formattedValue = formatValueForXml(stringValue, xsiType);
                    
                    xmlLines.add('        <value xsi:type="' + xsiType + '">' + escapeXml(formattedValue) + '</value>');
                    xmlLines.add('    </values>');
                }
            }
        }
        
        xmlLines.add('</CustomMetadata>');
        return String.join(xmlLines, '\n');
    }
    
    // Get field type map (combines your metadata calls)
    private static Map<String, String> getFieldTypeMap(String nc, String apiVersion, String typeId) {
        Map<String, String> fieldTypeMap = new Map<String, String>();
        
        try {
            List<Map<String, Object>> customFields = getCustomFieldDefinitions(nc, apiVersion, typeId);
            
            for (Map<String, Object> field : customFields) {
                String fieldId = (String) field.get('Id');
                HttpRequest metaReq = new HttpRequest();
                metaReq.setEndpoint('callout:' + nc + '/services/data/v60.0/tooling/sobjects/CustomField/' + fieldId);
                metaReq.setMethod('GET');
                
                HttpResponse metaRes = new Http().send(metaReq);
                Map<String, Object> parsedMeta = (Map<String, Object>) JSON.deserializeUntyped(metaRes.getBody());
                Map<String, Object> metadata = (Map<String, Object>) parsedMeta.get('Metadata');
                
                String fieldName = (String) field.get('DeveloperName');
                String dataType = (String) metadata.get('type');
                fieldTypeMap.put(fieldName, dataType);
            }
        } catch (Exception e) {
            System.debug('Error getting field types: ' + e.getMessage());
        }
        
        return fieldTypeMap;
    }
    
    // Find all record IDs for the custom metadata type
    private static List<String> findAllRecordIds(String nc, String customMetadataTypeName) {
        List<String> recordIds = new List<String>();
        
        try {
            Http http = new Http();
            String query = 'SELECT Id FROM ' + customMetadataTypeName;
            String endpoint = 'callout:' + nc + '/services/data/v59.0/query/?q=' + 
                EncodingUtil.urlEncode(query, 'UTF-8');
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) result.get('records');
                
                for (Object recObj : records) {
                    Map<String, Object> record = (Map<String, Object>) recObj;
                    recordIds.add((String) record.get('Id'));
                }
            }
        } catch (Exception e) {
            System.debug('Error finding record IDs: ' + e.getMessage());
        }
        
        return recordIds;
    }
    
    // Get custom field definitions
    private static List<Map<String, Object>> getCustomFieldDefinitions(String nc, String apiVersion, String typeId) {
        try {
            Http http = new Http();
            String toolingApiUrl = 'callout:' + nc + '/services/data/' + apiVersion + '/tooling/';
            
            String fieldsQuery = 'SELECT Id, DeveloperName, TableEnumOrId ' +
                'FROM CustomField ' +
                'WHERE TableEnumOrId = \'' + typeId + '\'';
            
            String fieldsEndpoint = toolingApiUrl + 'query/?q=' + EncodingUtil.urlEncode(fieldsQuery, 'UTF-8');
            
            HttpRequest fieldsReq = new HttpRequest();
            fieldsReq.setEndpoint(fieldsEndpoint);
            fieldsReq.setMethod('GET');
            fieldsReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse fieldsRes = http.send(fieldsReq);
            
            List<Map<String, Object>> customFields = new List<Map<String, Object>>();
            
            if (fieldsRes.getStatusCode() == 200) {
                Map<String, Object> fieldsResult = (Map<String, Object>) JSON.deserializeUntyped(fieldsRes.getBody());
                List<Object> fieldRecords = (List<Object>) fieldsResult.get('records');
                
                for (Object fieldObj : fieldRecords) {
                    customFields.add((Map<String, Object>) fieldObj);
                }
            }
            
            return customFields;
            
        } catch (Exception e) {
            System.debug('Error getting field definitions: ' + e.getMessage());
            return new List<Map<String, Object>>();
        }
    }
    
    // Get field values for a specific record
    private static Map<String, Object> getRecordFieldValues(
        String nc, 
        String apiVersion, 
        String recordId, 
        List<Map<String, Object>> customFields, 
        String recordName
    ) {
        Map<String, Object> fieldValues = new Map<String, Object>();
        
        try {
            // Get all field API names
            Http http = new Http();
            String toolingApiUrl = 'callout:' + nc + '/services/data/' + apiVersion + '/tooling/';
            String query = 'SELECT QualifiedApiName FROM EntityParticle WHERE EntityDefinitionId = \'' + recordId + '\'';
            String endpoint = toolingApiUrl + 'query/?q=' + EncodingUtil.urlEncode(query, 'UTF-8');

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');

            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> particles = (List<Object>) result.get('records');

                List<String> fieldApiNames = new List<String>();
                for (Object particleObj : particles) {
                    Map<String, Object> particle = (Map<String, Object>) particleObj;
                    String fieldName = (String) particle.get('QualifiedApiName');
                    if (fieldName != null && fieldName.endsWith('__c')) {
                        fieldApiNames.add(fieldName);
                    }
                }

                if (!fieldApiNames.isEmpty()) {
                    fieldApiNames.add('DeveloperName');
                    String soql = 'SELECT ' + String.join(fieldApiNames, ',') + ' FROM ' + recordName;
                    
                    HttpRequest dataReq = new HttpRequest();
                    dataReq.setEndpoint('callout:' + nc + '/services/data/v59.0/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8'));
                    dataReq.setMethod('GET');
                    
                    Http http1 = new Http();
                    HttpResponse dataRes = http1.send(dataReq);
                    
                    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(dataRes.getBody());
                    List<Object> records = (List<Object>) root.get('records');
                    
                    if (!records.isEmpty()) {
                        Map<String, Object> firstRecord = (Map<String, Object>) records[0];
                        
                        for (String apiName : fieldApiNames) {
                            Object value = firstRecord.get(apiName);
                            if (value != null) {
                                fieldValues.put(apiName, value);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting record values: ' + e.getMessage());
        }

        return fieldValues;
    }
    
    // Determine XSI type from Salesforce data type
    private static String determineXsiTypeFromDataType(String dataType) {
        if (dataType == null) return 'xsd:string';
        
        if (dataType == 'Boolean') {
            return 'xsd:boolean';
        } else if (dataType == 'Number' || dataType == 'Currency' || dataType == 'Percent' || dataType == 'Double') {
            return 'xsd:double';
        } else if (dataType == 'Date') {
            return 'xsd:date';
        } else if (dataType == 'DateTime') {
            return 'xsd:dateTime';
        } else if (dataType == 'Int' || dataType == 'Integer') {
            return 'xsd:integer';
        } else {
            return 'xsd:string';
        }
    }
    
    // Format value for XML based on type
    private static String formatValueForXml(String value, String xsiType) {
        if (value == null || value == '') return '';
        
        if (xsiType == 'xsd:boolean') {
            return value.toLowerCase();
        }
        
        if (xsiType == 'xsd:double' || xsiType == 'xsd:integer') {
            try {
                String cleanValue = value.replaceAll('[^0-9.-]', '');
                if (cleanValue != '') {
                    Decimal decValue = Decimal.valueOf(cleanValue);
                    return String.valueOf(decValue);
                }
            } catch (Exception e) {
                // If parsing fails, return original
            }
        }
        
        return value;
    }
    
    // Escape XML special characters
    private static String escapeXml(String input) {
        if (input == null) return '';
        return input
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&apos;');
    }
    
    // Save files as ContentVersion records
    public static List<ContentVersion> saveAsContentVersions(Map<String, String> filesMap) {
        List<ContentVersion> cvList = new List<ContentVersion>();
        
        for (String filePath : filesMap.keySet()) {
            String fileName = filePath.substringAfterLast('/');
            String xmlContent = filesMap.get(filePath);
            
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName.replace('.md-meta.xml', '');
            cv.PathOnClient = fileName;
            cv.VersionData = Blob.valueOf(xmlContent);
            
            cvList.add(cv);
        }
        
        if (!cvList.isEmpty()) {
            insert cvList;
            System.debug('Created ' + cvList.size() + ' ContentVersion records');
        }
        
        return cvList;
    }
    
    // Prepare output for Git/VS Code
    public static String prepareForGit(Map<String, String> filesMap) {
        List<String> output = new List<String>();
        output.add('// Copy and paste these files into your VS Code project:');
        output.add('// Directory structure: force-app/main/default/customMetadata/');
        output.add('');
        
        for (String filePath : filesMap.keySet()) {
            output.add('// File: ' + filePath);
            output.add(filesMap.get(filePath));
            output.add(''); // Empty line between files
        }
        
        return String.join(output, '\n');
    }

}