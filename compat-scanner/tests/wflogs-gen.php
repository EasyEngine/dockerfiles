<?php
// Regenerates tests/wflogs with Wordfence's own WAF code: its bootstrap creates the files, its storage writes the
// config, and its rule compiler writes rules.php from a small rule set (live sites download theirs).
// Usage: docker run --rm --network none -v <wordfence plugin dir>:/wf:ro -v <out>:/out -v "$PWD/tests:/t:ro" \
//          php:8.4.28-cli-alpine3.24 php /t/wflogs-gen.php
$_SERVER['REQUEST_URI'] = '/?q=1'; $_SERVER['HTTP_HOST'] = 'example.test'; $_SERVER['REQUEST_METHOD'] = 'GET';
$_SERVER['REMOTE_ADDR'] = '203.0.113.5'; $_SERVER['SCRIPT_FILENAME'] = '/site/index.php'; $_SERVER['DOCUMENT_ROOT'] = '/site';
define('WFWAF_LOG_PATH', '/out/wflogs/');
define('WFWAF_AUTO_PREPEND', true);
define('WFWAF_ALWAYS_ALLOW_FILE_WRITING', true); // CLI otherwise writes nothing
@mkdir('/out/wflogs', 0755, true);
include '/wf/waf/bootstrap.php';
if (class_exists('wfWAF') && wfWAF::getSharedStorageEngine()) {
	$s = wfWAF::getSharedStorageEngine();
	$s->setConfig('wafStatus', 'enabled');
	$s->setConfig('attackDataKey', 1234);
	$s->setConfig('learningModeGracePeriodEnabled', 0);
	$s->setConfig('cron', [ [ 'when' => time() ] ], 'livewaf');
	$s->setConfig('apiKey', 'x', 'synced');
	$s->setConfig('someTransient', 'y', 'transient');
	$s->blockIP(time() + 3600, "\xcb\x00q\x05");
	$s->saveConfig('livewaf'); $s->saveConfig('synced'); $s->saveConfig('transient'); $s->saveConfig();
}
$dsl = <<<'DSL'
scores.xss = 100
scores.sqli = 100
if (match('/<script/i', request.queryString) || contains('union select', request.body)):
    block(id=1, category='xss', score=100, title='XSS: script tag', description='Script tag in a parameter')
if (match('/union\s+select/i', request.queryString) && notequals('1', request.cookies[wf_test])):
    fail(id=2, category='sqli', score=100, title='SQL injection', description='SQLi in the query string')
if (equals('/xmlrpc.php', request.path) && match('/system\.multicall/i', request.rawBody)):
    block(id=3, category='brute-force', score=100, title='XML-RPC multicall', description='Multicall brute force')
DSL;
wfWAF::getInstance()->updateRuleSet($dsl, false);
echo "done\n";
