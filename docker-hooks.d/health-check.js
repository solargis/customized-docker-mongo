function exists(f) {
    try { md5sumFile(f); return true; }
    catch(e) { return false; }
}

load("/root/.mongorc.js");
let rs_status = rs.status();
if (rs_status.ok == 0) {
    if (rs_status.code == 94 && exists("/root/.replicaSet.js")) rs.initiate(load("/root/.replicaSet.js"));
    quit(1);
}
