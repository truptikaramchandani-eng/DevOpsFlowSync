public class CustomMetadataExporter {
    public static String getAllCustomMetadataRecordsXml(String nc, String customMetadataTypeName) {
        try {
            // First get all field definitions
            Http http = new Http();
            String apiVersion = 'v61.0';
            
            String apiName = customMetadataTypeName.endsWith('__mdt') ? 
                customMetadataTypeName : customMetadataTypeName + '__mdt';
            String displayName = apiName.replace('__mdt', '');
            String name = displayName;
            String noNamespace = name.contains('__')
                ? name.substringAfter('__')
                : name;
            System.debug('noNamespace'+noNamespace);
            // Get type definition
            String typeQuery = 'SELECT Id, DeveloperName, NamespacePrefix ' +
                'FROM CustomObject ' +
                'WHERE DeveloperName = \'' + String.escapeSingleQuotes(noNamespace) + '\'';
            
            String typeEndpoint = 'callout:'+ nc + '/services/data/' + apiVersion + '/tooling/query/?q=' + 
                EncodingUtil.urlEncode(typeQuery, 'UTF-8');
            
            HttpRequest typeReq = new HttpRequest();
            typeReq.setEndpoint(typeEndpoint);
            typeReq.setMethod('GET');
            typeReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse typeRes = http.send(typeReq);
            
            if (typeRes.getStatusCode() != 200) {
                return 'Error: ' + typeRes.getStatusCode() + ' - ' + typeRes.getBody();
            }
            
            Map<String, Object> typeResult = (Map<String, Object>) JSON.deserializeUntyped(typeRes.getBody());
            List<Object> typeRecords = (List<Object>) typeResult.get('records');
            
            if (typeRecords.isEmpty()) {
                return 'Error: Type not found';
            }
            
            Map<String, Object> typeRecord = (Map<String, Object>) typeRecords[0];
            String typeId = (String) typeRecord.get('Id');
            System.debug('typeRecord'+typeRecord);
            String namespacePrefix = (String) typeRecord.get('NamespacePrefix');
            
            /*String fullName = String.isNotBlank(namespacePrefix) ? 
                namespacePrefix + '__' + displayName : displayName;*/
            String fullName;
            // Get all custom fields with their DataType
            List<Map<String, Object>> customFields = getCustomFieldDefinitions(nc, apiVersion, typeId);
            
            // Find all record IDs
            List<String> recordIds = findAllRecordIds(nc, apiVersion, typeId);
            
            // Collect all field values from all records
            Map<String, Object> allFieldValues = new Map<String, Object>();
            Map<String, String> fieldTypeMap = new Map<String, String>();
            Map<String, String> fieldIdMap = new Map<String, String>();
            // Build field type map
            for (Map<String, Object> field : customFields) {
                System.debug('field'+field);
                Map<String, Object> attributes = (Map<String, Object>) field.get('attributes');
                String types = (String) attributes.get('type');
                System.debug('types'+types);
                    HttpRequest metaReq = new HttpRequest();
                    String fieldId = (String) field.get('Id');
                    metaReq.setEndpoint('callout:'+ nc + '/services/data/v60.0/tooling/sobjects/CustomField/' + fieldId);
                    metaReq.setMethod('GET');
                    
                    HttpResponse metaRes = new Http().send(metaReq);
                    Map<String,Object> parsedMeta = (Map<String,Object>) JSON.deserializeUntyped(metaRes.getBody());
                    System.debug('parsedMeta'+parsedMeta);
                    Map<String,Object> metadata = (Map<String,Object>) parsedMeta.get('Metadata');
                    String fieldName = (String) field.get('DeveloperName');
                    String dataType = (String) metadata.get('type');
                    System.debug('dataType'+dataType);
                    fieldTypeMap.put(fieldName, dataType);
            }
            
            // Get values from all records
            for (String recordId : recordIds) {
                System.debug('recordId'+recordId+' '+fieldIdMap.get(recordId));
                Map<String, Object> recordValues = getRecordFieldValues(nc, apiVersion, recordId, customFields, customMetadataTypeName);
                
                // Merge values (last record wins for duplicate field names)
                for (String fieldName : recordValues.keySet()) {
                    System.debug('recordValues.get(fieldName)'+recordValues.get(fieldName));
                    if(fieldName == 'DeveloperName'){
                        fullName = (String)recordValues.get(fieldName);
                    }
                    allFieldValues.put(fieldName, recordValues.get(fieldName));
                }
                
            }
            
            // Build XML
            List<String> xmlLines = new List<String>();
            xmlLines.add('<?xml version="1.0" encoding="UTF-8"?>');
            xmlLines.add('<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" ' +
                         'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                         'xmlns:xsd="http://www.w3.org/2001/XMLSchema">');
            
            xmlLines.add('    <label>' + fullName + '</label>');
            xmlLines.add('    <protected>false</protected>');
            
            // Sort field names alphabetically for consistent output
            List<String> sortedFieldNames = new List<String>(allFieldValues.keySet());
            sortedFieldNames.sort();
            List<ContentVersion> cvList = new List<ContentVersion>();
            for (String fieldName : sortedFieldNames) {
                if(fieldName!= 'DeveloperName'){
                    Object value = allFieldValues.get(fieldName);
                    
                    if (value != null) {
                        xmlLines.add('    <values>');
                        xmlLines.add('        <field>' + fieldName + '</field>');
                        
                        String stringValue = String.valueOf(value);
                        
                        String dataType = fieldTypeMap.get(fieldName.replaceAll('^[a-zA-Z0-9]+__', '').replaceAll('(__c|__mdt|__r)$', ''));
                        System.debug('fieldTypeMap'+fieldTypeMap);
                        System.debug('dataType+fieldName'+dataType);
                        String xsiType = determineXsiTypeFromDataType(dataType);
                        String formattedValue = formatValueForXml(stringValue, xsiType);
                        
                        xmlLines.add('        <value xsi:type="' + xsiType + '">' + formattedValue + '</value>');
                        xmlLines.add('    </values>');
                    }
                }
            }
            String displayName1 = 'Jira_Configuration__mdt';
            xmlLines.add('</CustomMetadata>');
            ContentVersion cv = new ContentVersion();
            cv.Title = displayName1 + '_Settings';
            cv.PathOnClient = displayName1 + '.settings-meta.xml';
            cv.VersionData = Blob.valueOf(String.join(xmlLines, '\n'));
            cvList.add(cv);
            if (!cvList.isEmpty()) insert cvList;
            return String.join(xmlLines, '\n');
            
        } catch (Exception e) {
            return 'Error: ' + e.getMessage() + ' (Line: ' + e.getLineNumber() + ')';
        }
    }
    
    private static List<Map<String, Object>> getCustomFieldDefinitions(String nc, String apiVersion, String typeId) {
        try {
            Http http = new Http();
            String toolingApiUrl =  'callout:'+ nc + '/services/data/' + apiVersion + '/tooling/';
            
            String fieldsQuery = 'SELECT Id,DeveloperName, TableEnumOrId ' +
                'FROM CustomField ' +
                'WHERE TableEnumOrId = \'' + typeId + '\' ';
            
            String fieldsEndpoint = toolingApiUrl + 'query/?q=' + EncodingUtil.urlEncode(fieldsQuery, 'UTF-8');
            
            HttpRequest fieldsReq = new HttpRequest();
            fieldsReq.setEndpoint(fieldsEndpoint);
            fieldsReq.setMethod('GET');
            fieldsReq.setHeader('Content-Type', 'application/json');
            
            HttpResponse fieldsRes = http.send(fieldsReq);
            
            List<Map<String, Object>> customFields = new List<Map<String, Object>>();
            
            if (fieldsRes.getStatusCode() == 200) {
                Map<String, Object> fieldsResult = (Map<String, Object>) JSON.deserializeUntyped(fieldsRes.getBody());
                System.debug('fieldsRes.getBody()'+fieldsRes.getBody());
                List<Object> fieldRecords = (List<Object>) fieldsResult.get('records');
                System.debug('fieldRecords'+fieldRecords);
                for (Object fieldObj : fieldRecords) {
                    customFields.add((Map<String, Object>) fieldObj);
                }
            }
            System.debug('customFields'+customFields);
            return customFields;
            
        } catch (Exception e) {
            System.debug('Error getting field definitions: ' + e.getMessage());
            return new List<Map<String, Object>>();
        }
    }
    
    private static Map<String, Object> getRecordFieldValues(String nc, String apiVersion, String recordId, List<Map<String, Object>> customFields, String recordName) {
    Map<String, Object> fieldValues = new Map<String, Object>();
    
    try {
        // 1. Get field API names using EntityParticle
        Http http = new Http();
        String toolingApiUrl = 'callout:'+ nc + '/services/data/' + apiVersion + '/tooling/';
        String query = 'SELECT DeveloperName, QualifiedApiName  FROM EntityParticle WHERE EntityDefinitionId = \'' + recordId + '\'';
        String endpoint = toolingApiUrl + 'query/?q=' + EncodingUtil.urlEncode(query, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');

        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> particles = (List<Object>) result.get('records');
			System.debug('result'+result);
            // Collect all custom field names
            List<String> fieldApiNames = new List<String>();
            for (Object particleObj : particles) {
                Map<String, Object> particle = (Map<String, Object>) particleObj;
                System.debug('particle'+particle);
                String fieldName = (String) particle.get('QualifiedApiName');
                if (fieldName != null && fieldName.endsWith('__c')) {
                    fieldApiNames.add(fieldName);
                    System.debug('fieldApiNames'+fieldApiNames);
                }
            }

            if (!fieldApiNames.isEmpty()) {
                // 2. Run SOQL to fetch ACTUAL field values
                fieldApiNames.add('DeveloperName');
                String soql = 'SELECT ' + String.join(fieldApiNames, ',') + ' FROM '+recordName;
                System.debug('soql'+soql);
                HttpRequest dataReq = new HttpRequest();
                dataReq.setEndpoint('callout:'+nc+'/services/data/v59.0/query/?q='+EncodingUtil.urlEncode(soql, 'UTF-8'));
                dataReq.setMethod('GET');
                
                Http http1 = new Http();
                HttpResponse dataRes = http1.send(dataReq);
                
                System.debug('Response: ' + dataRes.getBody());
                // Deserialize into a generic Map
                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(dataRes.getBody());
                
                // Extract the records list
                List<Object> records = (List<Object>) root.get('records');
                
                // Prepare a list of maps (in case multiple records are returned)
                List<Map<String, String>> allRecords = new List<Map<String, String>>();
                
                for (Object recObj : records) {
                    Map<String, Object> record = (Map<String, Object>) recObj;
                    Map<String, String> fieldMap = new Map<String, String>();
                    
                    // Loop through all keys dynamically
                    for (String key : record.keySet()) {
                        // Skip system attributes if you don’t want them
                        if (key != 'attributes') {
                            fieldMap.put(key, String.valueOf(record.get(key)));
                            System.debug('fieldMap'+fieldMap);
                        }
                    }
                    
                    allRecords.add(fieldMap);
                }
                
                // Debug the result
                System.debug('Dynamic Field Maps: ' + allRecords);
                //SObject rec = Database.query(soql);
				//System.debug('rec'+rec);
                //fieldValues = rec.getPopulatedFieldsAsMap();
                
                fieldValues = new Map<String, Object>();
                if (allRecords.size() == 1) {
                    Map<String, String> singleRecord = allRecords[0];
                    System.debug('Single Record Map: ' + singleRecord);
                    
                    // Example: access by API name
                    for (String apiName : fieldApiNames) {
                        Object value = singleRecord.get(apiName);
                        System.debug(apiName + ' = ' + value);
                        fieldValues.put(apiName, value);
                    }
                }
                
                // Case 2: Multiple records → loop through all
                else {
                    for (Map<String, String> recMap : allRecords) {
                        System.debug('Record Map: ' + recMap);
                        
                        for (String apiName : fieldApiNames) {
                            Object value = recMap.get(apiName);
                            System.debug(apiName + ' = ' + value);
                            fieldValues.put(apiName, value);
                        }
                    }
                }

                /*for (String apiName : fieldApiNames) {
                    System.debug('apiName'+apiName);
                    Object value = allRecords.get(apiName);
                    fieldValues.put(apiName, value);
                }*/
                System.debug('fieldValues = ' + fieldValues);
                System.debug('fieldValues'+fieldValues);
            }
        }
    } catch (Exception e) {
        System.debug('Error: ' + e.getMessage());
    }

    return fieldValues;
}

    private static String determineXsiTypeFromDataType(String dataType) {
        if (dataType == null) return 'xsd:string';
        
        // Map Salesforce DataType to XSD type
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
            return 'xsd:string'; // Default for Text, Picklist, TextArea, etc.
        }
    }
  
    private static String formatValueForXml(String value, String xsiType) {
        if (value == null || value == '') return '';
        
        if (xsiType == 'xsd:boolean') {
            return value.toLowerCase();
        }
        
        // For numbers, ensure proper format
        if (xsiType == 'xsd:double' || xsiType == 'xsd:integer') {
            try {
                // Remove any commas or currency symbols
                String cleanValue = value.replaceAll('[^0-9.-]', '');
                if (cleanValue != '') {
                    Decimal decValue = Decimal.valueOf(cleanValue);
                    return String.valueOf(decValue);
                }
            } catch (Exception e) {
                // If parsing fails, return original
            }
        }
        
        return escapeXml(value);
    }
    
    private static List<String> findAllRecordIds(String nc, String apiVersion, String typeId) {
        try {
            Http http = new Http();
            String toolingApiUrl =  'callout:'+ nc + '/services/data/' + apiVersion + '/tooling/';
            
            String query = 'SELECT Id, DeveloperName ' +
                'FROM CustomObject ' +
                'WHERE Id = \'' + typeId + '\' ' +
                'AND DeveloperName != null ' +
                'ORDER BY DeveloperName';
            
            String endpoint = toolingApiUrl + 'query/?q=' + EncodingUtil.urlEncode(query, 'UTF-8');
            System.debug('endpoint'+endpoint);
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            
            HttpResponse res = http.send(req);
            
            List<String> recordIds = new List<String>();
            System.debug('res.getBody()'+res.getBody());
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) result.get('records');
                
                for (Object recObj : records) {
                    System.debug('records'+records);
                    Map<String, Object> record = (Map<String, Object>) recObj;
                    recordIds.add((String) record.get('Id'));
                }
            }
            
            return recordIds;
            
        } catch (Exception e) {
            System.debug('Error finding record IDs: ' + e.getMessage());
            return new List<String>();
        }
    }
    
    private static String escapeXml(String input) {
        if (input == null) return '';
        return input
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&apos;');
    }
}