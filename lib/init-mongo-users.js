/**
 * Input of this script is variable config with structure like:
 * ```typescript
 *   type Config = Array<User> | User;
 *   type User = { user: string, pwd: string, roles: Array<Role> }
 *             | { user: string, pwd: string, dbroles: { [dbname]: Array<string> | string };
 *   type Role = { db: string, role: string };
 * ```
 *  Examples:
 * ```js
 *    // Natively as mongo accepts
 *    config = {
 *      user: "app_user",
 *      pwd: "app_pA5word",
 *      roles: [
 *        { db: "cache", role: "readWrite" },
 *        { db: "cache", role: "admin" },
 *        { db: "records", role: "readWrite" },
 *        { db: "records", role: "admin" }
 *      ]
 *    }
 *    // or simplified
 *    config = {
 *      user: "app_user",
 *      pwd: "app_pA5word",
 *      dbroles: { // property .dbroles will be transformed to format .roles
 *        cache: [ "readWrite", "admin" ],
 *        records: "readWrite,admin" // array or comma separated string is accepted
 *      }
 *    }
 * ```
 */

if (!Array.prototype.find) Array.prototype.find = function (callback, thisArg) {
	for (var i = 0; i < this.length; i++) {
		if (callback.call(thisArg, this[i], i, this)) return this[i];
	}
	return null;
};

if (!Array.isArray(config)) config = [config];
var result = { actions: [], current_users: {} };

if (typeof Object.values === 'undefined') Object.values = function (obj) {
	return Object.keys(obj).map(function (key) { return obj[key]; });
};

function areUsersEqual(wanted, actual, auth_db) {
    if (wanted.user != actual.user) throw new Error("Comparing diferent users '"+wanted.user+"'!='"+actual.user+"'");
    var diff = [];

	if (wanted.roles) wanted.roles.forEach(function (w) {
		if (!actual.roles.find(function (a) { return a.role === w.role && a.db === w.db; })) diff.push({state:'missing', role:w});
	});
	if (actual.roles) actual.roles.forEach(function (a){
		if (!wanted.roles.find(function (w) { return a.role === w.role && a.db === w.db; })) diff.push({state:'in_addition', role:a});
	});

	var ws = wanted.authenticationRestrictions || [];
	var as = actual.authenticationRestrictions || [];
	ws.forEach(function (w) {
		if (!as.find(function (a) {
			return a.clientSource === w.clientSource && a.serverAddress === w.serverAddress;
		})) diff.push({state:'missing', authenticationRestriction:w});
	});
	as.forEach(function (a) {
		if (!ws.find(function (w) {
			return a.clientSource === w.clientSource && a.serverAddress === w.serverAddress;
		})) diff.push({state:'in_addition', authenticationRestriction:a});
	});

    var db_name = auth_db.getName();
    print("Info: Trying to autheticate user '" + wanted.user + "' according to dbatabase '" + db_name + "'");
    if (auth_db.auth(wanted.user, wanted.pwd) == 1) {
        auth_db.logout();
        if (db_name == 'admin') do_auth();
    }
    else {
        diff.push({state:'password_not_working'});
    }

	return diff.length ? diff : null;
}

var dbs = { admin: db.getSiblingDB('admin') };
for (var i = 0; i < config.length; i++) {
	var user = config[i];
	var auth_dbs = { admin: dbs.admin };

	if (user.dbroles) {
		if (!user.roles) user.roles = [];
		Object.keys(user.dbroles).forEach(function (db) {
			if (!Array.isArray(user.dbroles[db])) user.dbroles[db] = user.dbroles[db].split(',');
			user.roles.push.apply(user.roles, user.dbroles[db].map(function (role) {
				return db ? { db: db, role: role.trim() } : { role: role.trim() };
			}));
		});
		delete user.dbroles;
	}

	if (user.roles) user.roles.forEach(function (role) {
		auth_dbs[role.db] = dbs[role.db] || (dbs[role.db] = db.getSiblingDB(role.db));
	});

	var auth_dbs_values = Object.values(auth_dbs);
	for (var j = 0; j < auth_dbs_values.length; j++) {
		var auth_db = auth_dbs_values[j];
		var db_name = auth_db.getName();
		var db_user = auth_db.getUser(user.user);
		var diff;
		if (!db_user) {
			auth_db.createUser(user)
			if (!(db_user = auth_db.getUser(user.user))) {
				print(JSON.stringify({input:user, command:"createUser", database:db_name }));
				quit(1);
			}
			result.actions.push({command:"createUser", user:user.user, database:db_name });
		} else if (diff = areUsersEqual(user, db_user, auth_db)) {
			var name = user.name;
			var updating = Object.assign({}, user);
			delete updating.name;
			auth_db.updateUser(name, updating);
			if (!!areUsersEqual(user, auth_db.getUser(user.user), auth_db)) {
				print(JSON.stringify({input:user, database:db_name, command:"updateUser", diff:diff }));
				quit(1);
			}
			result.actions.push({command:"updateUser", database:db_name, user:user.user, diff:diff });
        }
        delete db_user.userId;
		(result.current_users[user.user] || (result.current_users[user.user] = {auth_databases:{}})).auth_databases[db_name] = db_user;
	}
}
print(JSON.stringify(result));
