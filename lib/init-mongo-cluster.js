let result = Object.assign(rs.status(), {config});

function applyWithLog(label, fn, ...args) {
	let entry = { command: label, args, result: {} };
	try {
		entry.result = fn(...args);
	} catch (e) {
		entry.error = e.toString();
		entry.errorStack = e.stack.trim().split("\n");
	}
	(result.changes||(result.changes = [])).push(entry);
	return entry.result;
}

if (result.ok === 0 && result.code === 94) {
	let version = db.version();
	version = version.split(".")
	version = version.map(_ => parseInt(_));

	if (version[0] <= 3 && version[0] <= 4) {
		let hostPrefix = getHostName() + ":";
		let members = config.members.slice();
		let primary = members.splice(members.findIndex(m => m.host.startsWith(hostPrefix), 1), 1)[0];

		let lastResult = applyWithLog("rs.initiate", rs.initiate, Object.assign({}, config, { members: [primary] }));

		if (lastResult.ok) {
			for (let member of members) {
				lastResult = applyWithLog("rs.add", m => rs.add(m), member);
				let count = 0;
				while (lastResult.ok === 0 && lastResult.codeName === "NotMaster" && ++count < 5) {
					sleep(count * 10);
					lastResult = applyWithLog("rs.add", m => rs.add(m), member);
				}
				if (!lastResult.ok) break;
			}
		}
	}
	else applyWithLog("rs.initiate", rs.initiate, config);
}
if (result.ok === 1 && result.members.length < result.config.members.length) {
	for (let member of result.config.members) {
		if (!result.members.find(m => m.name === member.host)) {
			let lastResult = applyWithLog("rs.add", m => rs.add(m), member);
			if (!lastResult.ok) break;
		}
	}
}
result.ready = result.ok === 1 && result.members.length === result.config.members.length && !!result.members.find(m => m.state === 1);
print(JSON.stringify(result));
