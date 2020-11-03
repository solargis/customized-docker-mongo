if (!Array.isArray(config)) config = [config];
let result = { actions: [], current_users: {} };

if (typeof Object.values === 'undefined') Object.values = obj => Object.keys(obj).map(key => obj[key]);

function areUsersEqual(wanted, actual, auth_db) {
    if (wanted.user != actual.user) throw new Error("Comparing diferent users '"+wanted.user+"'!='"+actual.user+"'");
    let diff = [];

    for (let w of wanted.roles||[]) if (!actual.roles.find(a => a.role === w.role && a.db === w.db )) diff.push({state:'missing', role:w});
    for (let a of actual.roles||[]) if (!wanted.roles.find(w => a.role === w.role && a.db === w.db )) diff.push({state:'in_addition', role:a});

    let [ws, as] = [wanted.authenticationRestrictions||[],actual.authenticationRestrictions||[]]
    for (let w of ws) if (!as.find(a => a.clientSource === w.clientSource && a.serverAddress === w.serverAddress )) diff.push({state:'missing', authenticationRestriction:w});
    for (let a of as) if (!ws.find(w => a.clientSource === w.clientSource && a.serverAddress === w.serverAddress )) diff.push({state:'in_addition', authenticationRestriction:a});

    let db_name = auth_db.getName();
    print(`Info: Trying to autheticate user '${wanted.user}' according to dbatabase '${db_name}'`);
    if (auth_db.auth(wanted.user, wanted.pwd) == 1) {
        auth_db.logout();
        if (db_name == 'admin') do_auth();
    }
    else {
        diff.push({state:'password_not_working'});
    }

	return diff.length ? diff : null;
}

let dbs = { admin: db.getSiblingDB('admin') };
for (let user of config) {
	let auth_dbs = { admin: dbs.admin };
	(user.roles || []).forEach(role => {
		auth_dbs[role.db] = dbs[role.db] || (dbs[role.db] = db.getSiblingDB(role.db));
	});
	for (let auth_db of Object.values(auth_dbs)) {
		let db_name = auth_db.getName();
		let db_user = auth_db.getUser(user.user);
		let diff;
		if (!db_user) {
			auth_db.createUser(user)
			if (!(db_user = auth_db.getUser(user.user))) {
				print(JSON.stringify({input:user, command:"createUser", database:db_name }));
				quit(1);
			}
			result.actions.push({command:"createUser", user:user.user, database:db_name });
		} else if (diff = areUsersEqual(user, db_user, auth_db)) {
			let name = user.name;
			let updating = Object.assign({}, user);
			delete updating.name;
			auth_db.updateUser(name, updating);
			if (!!areUsersEqual(user, auth_db.getUser(user.user), auth_db)) {
				print(JSON.stringify({input:user, database:db_name, command:"updateUser", diff }));
				quit(1);
			}
			result.actions.push({command:"updateUser", database:db_name, user:user.user, diff });
        }
        delete db_user.userId;
		(result.current_users[user.user] || (result.current_users[user.user] = {auth_databases:{}})).auth_databases[db_name] = db_user;
	}
}
print(JSON.stringify(result));
