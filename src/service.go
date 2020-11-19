package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"reflect"
	"regexp"
	"strings"
	"time"
)

// State `json:"action,omitempty"`
type State struct {
	Ok          bool `json:"ok"`
	InitCluster struct {
		Try      int            `json:"tries"`
		Complete bool           `json:"complete"`
		Status   *clusterStatus `json:"status,omitempty"`
		Error    []string       `json:"error,omitempty"`
	} `json:"init_cluster"`
	InitUsers struct {
		Try      int                    `json:"tries"`
		Complete bool                   `json:"complete"`
		Status   map[string]interface{} `json:"status"`
		Error    []string               `json:"error,omitempty"`
	} `json:"init_users"`
}

var (
	state         State = State{}
	port          int   = 8090
	warningLogger *log.Logger
	infoLogger    *log.Logger
	errorLogger   *log.Logger
)

func init() {
	logFlags := log.Ldate | log.Ltime | log.Lshortfile
	infoLogger = log.New(os.Stdout, "[INFO ] ", logFlags)
	warningLogger = log.New(os.Stdout, "[WARN ] ", logFlags)
	errorLogger = log.New(os.Stdout, "[ERROR] ", logFlags)
}

func find(arr []statusMember, test func(statusMember) bool) *statusMember {
	for _, elm := range arr {
		if test(elm) {
			return &elm
		}
	}
	return nil
}

func containsAny(arr []string, samples ...string) bool {
	for _, item := range arr {
		for _, sample := range samples {
			if item == sample {
				return true
			}
		}
	}
	return false
}

func status(w http.ResponseWriter, req *http.Request) {
	response, err := json.MarshalIndent(&state, "", "  ")
	if err != nil {
		errorLogger.Println(err.Error())
		http.Error(w, err.Error(), http.StatusInternalServerError)
	} else {
		w.Header().Set("Content-Type", "application/json")
		w.Write(response)
		w.Write([]byte("\n"))
	}
}

func healthcheck(w http.ResponseWriter, req *http.Request) {
	_, noPrimary := req.URL.Query()["noPrimary"]
	if state.Ok && verifyMongoState(!noPrimary) {
		w.WriteHeader(http.StatusNoContent)
		w.Write([]byte("healthy"))
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("unhealthy"))
	}
}

func favicon(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "image/svg+xml")
	w.Header().Set("Cache-Control", "max-age=172800") // 2 days
	// https://www.iconfinder.com/editor/?id=1012822&hash=d36678d620f2bb66710e1be8a8b047bf177ac72f03253c48b931964d
	w.Write([]byte(`<svg width="16" height="16" xmlns="http://www.w3.org/2000/svg">
<g>
	<title>background</title>
	<rect fill="none" id="canvas_background" height="18" width="18" y="-1" x="-1"/>
</g>
<g>
	<title>Layer 1</title>
	<g stroke="null" id="svg_5">
	<path stroke="null" fill="#ffffff" id="svg_6" d="m8.095937,15.849188l-0.480796,-0.142834c0,0 0.053422,-2.166321 -0.814682,-2.321059c-0.574284,-0.595143 0.093488,-25.460227 2.176937,-0.08332c0,0 -0.721194,0.321377 -0.841393,0.868909c-0.133554,0.535629 -0.040066,1.678304 -0.040066,1.678304l0,0l0,0z" class="st2"/>
	<path stroke="null" fill="#a6a385" id="svg_7" d="m8.095937,15.849188l-0.480796,-0.142834c0,0 0.053422,-2.166321 -0.814682,-2.321059c-0.574284,-0.595143 0.093488,-25.460227 2.176937,-0.08332c0,0 -0.721194,0.321377 -0.841393,0.868909c-0.133554,0.535629 -0.040066,1.678304 -0.040066,1.678304l0,0l0,0z" class="st3"/>
	<path stroke="null" fill="#ffffff" id="svg_8" d="m8.34969,13.754284c0,0 4.166898,-2.440087 3.191951,-7.52261c-0.934881,-3.689888 -3.16524,-4.90398 -3.405638,-5.368192c-0.267109,-0.33328 -0.520862,-0.916521 -0.520862,-0.916521l0.173621,10.272172c0.013355,0.023806 -0.347242,3.154259 0.560929,3.535151" class="st2"/>
	<path stroke="null" fill="#499d4a" id="svg_9" d="m8.34969,13.754284c0,0 4.166898,-2.440087 3.191951,-7.52261c-0.934881,-3.689888 -3.16524,-4.90398 -3.405638,-5.368192c-0.267109,-0.33328 -0.520862,-0.916521 -0.520862,-0.916521l0.173621,10.272172c0.013355,0.023806 -0.347242,3.154259 0.560929,3.535151" class="st4"/>
	<path stroke="null" fill="#ffffff" id="svg_10" d="m7.374743,13.897118c0,0 -3.913145,-2.380573 -3.686102,-6.570381c0.227043,-4.189808 2.978264,-6.249004 3.512482,-6.629895c0.360597,-0.33328 0.373952,-0.452309 0.400663,-0.785589c0.240398,0.464212 0.200332,6.963176 0.227043,7.736862c0.106844,2.940007 -0.186976,5.689569 -0.454085,6.249004l0,0l0,0z" class="st2"/>
	<path stroke="null" fill="#58aa50" id="svg_11" d="m7.374743,13.897118c0,0 -3.913145,-2.380573 -3.686102,-6.570381c0.227043,-4.189808 2.978264,-6.249004 3.512482,-6.629895c0.360597,-0.33328 0.373952,-0.452309 0.400663,-0.785589c0.240398,0.464212 0.200332,6.963176 0.227043,7.736862c0.106844,2.940007 -0.186976,5.689569 -0.454085,6.249004l0,0l0,0z" class="st5"/>
	</g>
</g>
</svg>`))
}

func serve() {
	http.HandleFunc("/favicon.ico", favicon)
	http.HandleFunc("/healthcheck", healthcheck)
	http.HandleFunc("/", status)
	infoLogger.Printf("Starting service http://localhost:%d/", port)
	http.ListenAndServe(fmt.Sprintf(":%d", port), nil)
}

func replSetConnectArgs(db string) []string {
	if state.InitCluster.Status != nil && (*state.InitCluster.Status).Ok == 1 {
		nodes := make([]string, len((*state.InitCluster.Status).Members))
		for i, member := range (*state.InitCluster.Status).Members {
			nodes[i] = member.Name
		}
		username, password := os.Getenv("MONGO_INITDB_ROOT_USERNAME"), os.Getenv("MONGO_INITDB_ROOT_PASSWORD")
		result := []string{"db_address://" + strings.Join(nodes, ",")}
		if db != "" {
			result[0] = result[0] + "/" + db
		}
		if username != "" && password != "" {
			result = append(result, "--username", username, "--password", password, "--authenticationDatabase", "admin")
		}
		return result
	}
	if db != "" {
		return []string{"db_address://" + db}
	}
	return []string{}
}

func mongoEval(js ...string) (string, error) {
	infoLogger.Printf("evaluating: %+v", js)
	opts := []string{"--quiet"}
	scripts := []string{}
	var eval, dbAddress string

	skip := 0
	for i, entry := range js {
		if skip > 0 {
			skip--
		} else if strings.HasPrefix(entry, "--") || strings.HasPrefix(entry, "-") && len(entry) == 2 {
			if containsAny([]string{entry}, "-u", "--username", "-p", "--password", "--port", "--authenticationDatabase", "--authenticationMechanism") {
				skip++
				opts = append(opts, entry, js[i+1])
			} else {
				panic(fmt.Sprintf("Unknown argument %s", entry))
			}
		} else if len(entry) > 3 && entry[len(entry)-3:] == ".js" {
			scripts = append(scripts, entry)
		} else if strings.HasPrefix(entry, "mongodb://") {
			dbAddress = entry
		} else if strings.HasPrefix(entry, "db_address://") {
			dbAddress = entry[len("db_address://"):]
		} else {
			eval = fmt.Sprintf("%s\n%s", eval, entry)
		}
	}

	username, password := os.Getenv("MONGO_INITDB_ROOT_USERNAME"), os.Getenv("MONGO_INITDB_ROOT_PASSWORD")
	if username != "" && password != "" {
		invoke, doAuth := "", fmt.Sprintf("function do_auth() { db.getSiblingDB('admin').auth('%s','%s'); }", username, password)
		if !strings.Contains(dbAddress, "@") && !containsAny(opts, "-u", "--username") && !containsAny(opts, "-p", "--password") {
			invoke = "do_auth();"
		}
		m1 := regexp.MustCompile(`\n{2,}`)
		eval = m1.ReplaceAllString(strings.TrimSpace(strings.Join([]string{doAuth, invoke, eval}, "\n")), "\n")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if dbAddress != "" {
		opts = append([]string{dbAddress}, opts...)
	}
	if eval != "" {
		opts = append(opts, "--eval", eval)
	}
	if len(scripts) > 0 {
		opts = append(opts, scripts...)
	}

	infoLogger.Print("excuting: mongo " + formatCommand(opts))
	cmd := exec.CommandContext(ctx, "mongo", opts...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		errorLogger.Print(fmt.Sprintf("%s\n%s", err, string(out)))
	}
	return string(out), err
}

func formatCommand(opts []string) string {
	password := os.Getenv("MONGO_INITDB_ROOT_PASSWORD")
	formated := make([]string, len(opts))
	for i, opt := range opts {
		expandable := false
		if password != "" {
			if strings.HasPrefix(opt, "mongodb://") {
				opt = strings.Replace(opt, ":"+password+"@", ":$MONGO_INITDB_ROOT_PASSWORD@", 1)
				expandable = true
			} else if i > 0 && opts[i-1] == "--eval" {
				opt = strings.Replace(opt, "'"+password+"'", "'*****'", 1)
			}
		}
		if expandable {
			opt = "\"" + strings.ReplaceAll(opt, "\"", "\\\"") + "\""
		} else if strings.ContainsAny(opt, " \n\t&") {
			opt = "'" + strings.ReplaceAll(opt, "'", "'\"'\"'") + "'"
		}
		formated[i] = opt
	}
	return strings.Join(formated, " ")
}

// ConfigMenber https://docs.mongodb.com/manual/reference/replica-configuration/#members
type ConfigMenber struct {
	ID           int                `json:"_id"`
	Host         string             `json:"host"`
	ArbiterOnly  *bool              `json:"arbiterOnly,omitempty"`
	BuildIndexes *bool              `json:"buildIndexes,omitempty"`
	Hidden       *bool              `json:"hidden,omitempty"`
	Priority     *int               `json:"priority,omitempty"`
	Tags         *map[string]string `json:"tags,omitempty"`
	SlaveDelay   *int64             `json:"slaveDelay,omitempty"`
	Votes        *int               `json:"votes,omitempty"`
}
type statusMember struct {
	Name     string `json:"name"`
	Health   int    `json:"health"`
	State    int    `json:"state"` // https://docs.mongodb.com/manual/reference/replica-states/
	StateStr string `json:"stateStr"`
}
type clusterStatus struct {
	Ok           int            `json:"ok"`
	ErrorCode    int            `json:"code,omitempty"`
	ErrorName    string         `json:"codeName,omitempty"`
	Messages     []string       `json:"messages,omitempty"`
	ErrorMessage string         `json:"errmsg,omitempty"`
	MyState      int            `json:"myState,omitempty"`
	Members      []statusMember `json:"members,omitempty"`
	Set          string         `json:"set,omitempty"`
	Config       struct {
		ID      string         `json:"_id"`
		Members []ConfigMenber `json:"members"`
	} `json:"config,omitempty"`
	Changes []map[string]interface{} `json:"changes,omitempty"`
}

func verifyMongoState(withPrimary bool) bool {
	tests := []string{"rs.status().ok === 1", "db.stats().ok === 1"}
	if withPrimary {
		tests = append(tests, "!!rs.status().members.find(m => m.state === 1)")
	}
	out, err := mongoEval("print(" + strings.Join(tests, " && ") + ");")
	if err != nil {
		errorLogger.Println(err.Error())
	} else {
		aux := strings.Split(strings.TrimSpace(out), "\n")
		out = aux[len(aux)-1]
	}
	return err == nil && strings.TrimSpace(out) == "true"
}

func initClusterConfig(config string) bool {
	state.InitCluster.Try++
	out, err := mongoEval(fmt.Sprintf("var config = %s;", config), "/usr/local/lib/init-mongo-cluster.js")
	if err == nil {
		infoLogger.Println("Raw result of init-mongo-cluster.js:", string(out))
		dat := clusterStatus{}
		if len(out) > 0 {

			if err := json.Unmarshal([]byte(out), &dat); err != nil {
				panic(err)
			}
			var result, _ = json.Marshal(dat)
			infoLogger.Println(string(result))
			if state.InitCluster.Status != nil && state.InitCluster.Status.Changes != nil {
				if dat.Changes == nil {
					dat.Changes = state.InitCluster.Status.Changes
				} else {
					dat.Changes = append(state.InitCluster.Status.Changes, dat.Changes...)
				}
			}
			state.InitCluster.Status = &dat
			state.InitCluster.Error = nil
			return dat.Ok == 1 &&
				len(dat.Members) == len(dat.Config.Members) &&
				find(dat.Members, func(it statusMember) bool { return it.State == 1 }) != nil
		}
	} else {
		state.InitCluster.Error = strings.Split(strings.TrimSpace(fmt.Sprintf("%s\n%s", err, string(out))), "\n")
	}
	return false
}

func isArray(s interface{}) bool {
	if s == nil {
		return false
	}
	switch reflect.TypeOf(s).Kind() {
	case reflect.Array:
		return true
	case reflect.Slice:
		return true
	default:
		return false
	}
}

func initUsersConfig(config string) bool {
	state.InitUsers.Try++
	out, err := mongoEval(append(replSetConnectArgs(""), fmt.Sprintf("var config = %s;", config), "/usr/local/lib/init-mongo-users.js")...)
	if err == nil {
		infoLogger.Println("Raw result of init-mongo-users.js:", string(out))
		if len(out) > 0 {
			messages, parsed := parseMongoResult(out, &state.InitUsers.Status)
			if parsed && len(messages) > 0 {
				messages = append([]string{fmt.Sprintf("---[ %d. exectution (success) ]:", state.InitUsers.Try)}, messages...)
				if isArray(state.InitUsers.Status["messages"]) {
					state.InitUsers.Status["messages"] = append(state.InitUsers.Status["messages"].([]string), messages...)
				} else if state.InitUsers.Error != nil {
					state.InitUsers.Status["messages"] = append(state.InitUsers.Error, messages...)
				} else {
					state.InitUsers.Status["messages"] = messages
				}
			}
			result, _ := json.Marshal(state.InitUsers.Status)
			infoLogger.Println(string(result))
			state.InitUsers.Error = nil
			return parsed
		}
	} else {
		messages := strings.Split(strings.TrimSpace(fmt.Sprintf("%s\n%s", err, string(out))), "\n")
		messages = append([]string{fmt.Sprintf("---[ %d. exectution (failed) ]:", state.InitUsers.Try)}, messages...)
		if state.InitUsers.Error != nil {
			state.InitUsers.Error = append(state.InitUsers.Error, messages...)
		} else {
			state.InitUsers.Error = messages
		}
	}
	return false
}

func parseMongoResult(result string, v interface{}) ([]string, bool) {
	lines := strings.Split(result, "\n")
	out := []string{}
	var err error
	var parsed bool
	for _, line := range lines {
		if line == "" {
			continue
		}
		if line[:1] == "{" {
			err = json.Unmarshal([]byte(line), v)
			if err != nil {
				out = append(out, line)
			} else {
				parsed = true
			}
		} else {
			out = append(out, line)
		}
	}
	return out, parsed
}

func applyState(init func() bool) {
	for !init() {
		time.Sleep(3 * time.Second)
	}
}

func provision() {
	time.Sleep(3 * time.Second)
	if os.Getenv("INIT_CLUSTER") != "" {
		applyState(func() bool {
			return initClusterConfig(os.Getenv("INIT_CLUSTER"))
		})
		state.InitCluster.Complete = true
	}
	if os.Getenv("INIT_USERS") != "" {
		applyState(func() bool {
			return initUsersConfig(os.Getenv("INIT_USERS"))
		})
		state.InitUsers.Complete = true
	}
	state.Ok = true
}

func dumpEnv() {
	for _, e := range os.Environ() {
		infoLogger.Println(e)
	}
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "check" {
		infoLogger.SetOutput(ioutil.Discard)
		withPrimary := len(os.Args) > 2 && os.Args[2] == "--with-primary"
		if verifyMongoState(withPrimary) {
			os.Exit(0)
		} else {
			os.Exit(1)
		}
	}
	// dumpEnv()
	go provision()
	serve()
}
