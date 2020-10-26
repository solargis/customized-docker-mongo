let result = rs.status();
if (result.ok == 0 && result.code == 94) {
	result.modified = true;
	result.modify_result = rs.initiate(config);
}
else if (result.ok == 1) {
	result.ready = !!result.members.find(m => m.state === 1);
}
print(JSON.stringify(Object.assign(result, {config})));
