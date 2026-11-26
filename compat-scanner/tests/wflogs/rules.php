<?php
if (!defined('WFWAF_VERSION') || defined('WFWAF_RULES_LOADED')) {
	exit('Access denied');
}
/*
	This file is generated automatically. Any changes made will be lost.
*/

$this->failScores['xss'] = 100;
$this->failScores['sqli'] = 100;




$this->rules[1] = wfWAFRule::create($this, 1, NULL, 'xss', '100', 'Script tag in a parameter', 1, 'block', new wfWAFRuleComparisonGroup(new wfWAFRuleComparison($this, 'match', '/<script/i', array(wfWAFRuleComparisonSubject::create($this, 'request.queryString', array (
)))), new wfWAFRuleLogicalOperator('||'), new wfWAFRuleComparison($this, 'contains', 'union select', array(wfWAFRuleComparisonSubject::create($this, 'request.body', array (
))))));
$this->rules[2] = wfWAFRule::create($this, 2, NULL, 'sqli', '100', 'SQLi in the query string', 1, 'fail', new wfWAFRuleComparisonGroup(new wfWAFRuleComparison($this, 'match', '/union\\s+select/i', array(wfWAFRuleComparisonSubject::create($this, 'request.queryString', array (
)))), new wfWAFRuleLogicalOperator('&&'), new wfWAFRuleComparison($this, 'notequals', '1', array(wfWAFRuleComparisonSubject::create($this, array('request.cookies', \wfWAFRuleVariable::__set_state(array(
   'name' => 'wf_test',
   'value' => NULL,
   'waf' => 
  \wfWAFWordPress::__set_state(array(
     'sqliBudget' => NULL,
     'sqliLimitLogged' => false,
     'blacklistedParams' => 
    array (
    ),
     'whitelistedParams' => 
    array (
    ),
     'variables' => 
    array (
    ),
     'rulesFile' => '/out/wflogs/rules.php',
     'trippedRules' => 
    array (
    ),
     'failedRules' => 
    array (
    ),
     'scores' => 
    array (
    ),
     'scoresXSS' => 
    array (
    ),
     'failScores' => 
    array (
    ),
     'rules' => 
    array (
    ),
     'request' => 
    \wfWAFWordPressRequest::__set_state(array(
       'auth' => 
      array (
      ),
       'body' => 
      array (
      ),
       'rawBody' => '',
       'md5Body' => 
      array (
      ),
       'jsonBody' => NULL,
       'jsonParsed' => false,
       'cookies' => 
      array (
      ),
       'fileNames' => 
      array (
      ),
       'files' => 
      array (
      ),
       'headers' => 
      array (
        'Host' => 'example.test',
      ),
       'host' => 'example.test',
       'ip' => '',
       'method' => 'GET',
       'path' => '/',
       'protocol' => 'http',
       'queryString' => 
      array (
      ),
       'md5QueryString' => 
      array (
      ),
       'timestamp' => 1795602343.811938,
       'uri' => '/?q=1',
       'metadata' => 
      array (
      ),
       'highlightParamFormat' => NULL,
       'highlightMatchFormat' => NULL,
       'highlightMatches' => NULL,
       'highlightMatchFilter' => 'urlencode',
    )),
     'storageEngine' => 
    \wfWAFStorageFile::__set_state(array(
       'rules' => NULL,
       'failScores' => NULL,
       'variables' => NULL,
       'whitelistedParams' => NULL,
       'blacklistedParams' => NULL,
       'ipCacheFileHandle' => NULL,
       'attackDataFile' => '/out/wflogs/attack-data.php',
       'attackDataEngine' => 
      \wfWAFAttackDataStorageFileEngine::__set_state(array(
         'file' => '/out/wflogs/attack-data.php',
         'fileHandle' => NULL,
         'header' => 
        array (
        ),
         'offsetTable' => 
        array (
        ),
      )),
       'ipCacheFile' => '/out/wflogs/ips.php',
       'configFile' => '/out/wflogs/config.php',
       'rulesFile' => '/out/wflogs/rules.php',
       'rulesDSLCacheFile' => '/out/wflogs/wafRules.rules',
       'dataChanged' => 
      array (
        'livewaf' => 
        array (
          0 => 'cron',
          1 => true,
        ),
        'transient' => 
        array (
          0 => 'attackDataNextInterval',
          1 => true,
        ),
        'synced' => 
        array (
          0 => 'apiKey',
          1 => true,
        ),
        '' => 
        array (
          0 => 'version',
          1 => true,
        ),
      ),
       'data' => 
      array (
        '' => 
        array (
          'wafStatus' => 'enabled',
          'learningModeGracePeriodEnabled' => 0,
          'learningModeGracePeriod' => 1796207143,
          'authKey' => '^h4dT!HP3>5bN#,25ZNI YB1P2<6B82=ukI3@ZR$Q7%Y-5fL>aoKWeV)E^$hOU:<',
          'version' => '1.1.0',
          'attackDataKey' => 1234,
        ),
        'synced' => 
        array (
          'apiKey' => 'x',
          'isPaid' => NULL,
          'siteURL' => NULL,
          'homeURL' => NULL,
          'whitelistedIPs' => NULL,
          'howGetIPs' => NULL,
          'howGetIPs_trusted_proxies' => NULL,
          'howGetIPs_trusted_proxies_unified' => NULL,
          'pluginABSPATH' => NULL,
          'other_WFNet' => NULL,
          'serverIPs' => NULL,
          'blockCustomText' => NULL,
          'timeoffset_wf' => NULL,
          'advancedBlockingEnabled' => NULL,
          'disableWAFIPBlocking' => NULL,
          'patternBlocks' => NULL,
          'countryBlocks' => NULL,
          'otherBlocks' => NULL,
          'lockouts' => NULL,
        ),
        'livewaf' => 
        array (
          'cron' => 
          array (
            0 => 
            array (
              'when' => 1795602344,
            ),
          ),
          'whitelistedURLParams' => NULL,
        ),
        'transient' => 
        array (
          'attackDataNextInterval' => NULL,
          'rulesLastUpdated' => NULL,
          'premiumCount' => NULL,
          'filePatterns' => NULL,
          'filePatternCommonStrings' => NULL,
          'filePatternIndexes' => NULL,
          'signaturesLastUpdated' => NULL,
          'signaturePremiumCount' => NULL,
          'createInitialRulesDelay' => NULL,
          'watchedIPs' => NULL,
          'blockedPrefixes' => NULL,
          'blacklistAllowedCache' => NULL,
          'someTransient' => 'y',
        ),
      ),
       'freshInstallation' => true,
       'configReadAttempt' => NULL,
       'configFileHandles' => 
      array (
        '' => NULL,
        'synced' => NULL,
        'livewaf' => NULL,
        'transient' => NULL,
      ),
       'uninstalled' => NULL,
       'attackDataRows' => NULL,
       'attackDataNewerThan' => NULL,
       'rowsToB64' => 
      array (
        0 => 3,
        1 => 4,
        2 => 7,
      ),
    )),
     'eventBus' => 
    \wfWAFEventBus::__set_state(array(
       'observers' => 
      array (
        0 => 
        \wfWAFWordPressObserver::__set_state(array(
           'waf' => NULL,
        )),
      ),
    )),
     'debug' => 
    array (
    ),
     'disabledRules' => 
    array (
    ),
     'runtimeLearningMode' => true,
     'publicKey' => '-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzovUDp/qu7r6LT5d8dLL
H/87aRrCjUd6XtnG+afAPVfMKNp4u4L+UuYfw1RfpfquP/zLMGdfmJCUp/oJywkW
Rkqo+y7pDuqIFQ59dHvizmYQRvaZgvincBDpey5Ek9AFfB9fqYYnH9+eQw8eLdQi
h6Zsh8RsuxFM2BW6JD9Km7L5Lyxw9jU+lye7I3ICYtUOVxc3n3bJT2SiIwHK57pW
g/asJEUDiYQzsaa90YPOLdf1Ysz2rkgnCduQaEGz/RPhgUrmZfKwq8puEmkh7Yee
auEa+7b+FGTKs7dUo2BNGR7OVifK4GZ8w/ajS0TelhrSRi3BBQCGXLzUO/UURUAh
1QIDAQAB
-----END PUBLIC KEY-----',
     'learningMode' => true,
     'learningModeAttackException' => NULL,
  )),
))), array (
))))));
$this->rules[3] = wfWAFRule::create($this, 3, NULL, 'brute-force', '100', 'Multicall brute force', 1, 'block', new wfWAFRuleComparisonGroup(new wfWAFRuleComparison($this, 'equals', '/xmlrpc.php', array(wfWAFRuleComparisonSubject::create($this, 'request.path', array (
)))), new wfWAFRuleLogicalOperator('&&'), new wfWAFRuleComparison($this, 'match', '/system\\.multicall/i', array(wfWAFRuleComparisonSubject::create($this, 'request.rawBody', array (
))))));
?>