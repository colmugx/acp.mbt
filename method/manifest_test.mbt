///|
using @protocol {protocol_parse_json}

///|
using @agent_message {decode_agent_request, decode_agent_notification}

///|
using @client_message {decode_client_request, decode_client_notification}

///|
fn manifest_method_names(methods : Array[AcpV1Method]) -> Array[String] {
  let names : Array[String] = []
  for entry in methods {
    names.push(entry.method_name)
  }
  names
}

///|
fn manifest_has_name(methods : Array[AcpV1Method], wanted : String) -> Bool {
  for entry in methods {
    if entry.method_name == wanted {
      return true
    }
  }
  false
}

///|
fn manifest_test_params(method_name : String) -> Json {
  let source = match method_name {
    "initialize" => "{\"protocolVersion\":1}"
    "authenticate" => "{\"methodId\":\"token\"}"
    "logout" => "{}"
    "session/new" => "{\"cwd\":\"/\",\"mcpServers\":[]}"
    "session/load" => "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}"
    "session/resume" => "{\"sessionId\":\"s\",\"cwd\":\"/\"}"
    "session/fork" => "{\"sessionId\":\"s\",\"cwd\":\"/\"}"
    "session/list" => "{}"
    "session/delete" => "{\"sessionId\":\"s\"}"
    "session/close" => "{\"sessionId\":\"s\"}"
    "session/set_mode" => "{\"sessionId\":\"s\",\"modeId\":\"code\"}"
    "session/set_config_option" =>
      "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}"
    "session/prompt" => "{\"sessionId\":\"s\",\"prompt\":[]}"
    "session/cancel" => "{\"sessionId\":\"s\"}"
    "session/request_permission" =>
      "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"call\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}"
    "fs/read_text_file" => "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}"
    "fs/write_text_file" =>
      "{\"sessionId\":\"s\",\"path\":\"/tmp/a\",\"content\":\"body\"}"
    "terminal/create" => "{\"sessionId\":\"s\",\"command\":\"echo\"}"
    "terminal/output" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "terminal/wait_for_exit" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "terminal/kill" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "terminal/release" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "elicitation/create" =>
      "{\"mode\":\"form\",\"message\":\"Choose\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}},\"requestId\":1}"
    "session/update" =>
      "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}"
    "elicitation/complete" => "{\"elicitationId\":\"e\"}"
    "$/cancel_request" => "{\"requestId\":1}"
    _ => abort("missing stable manifest fixture for " + method_name)
  }
  protocol_parse_json(source) catch {
    _ => abort("invalid stable manifest fixture for " + method_name)
  }
}

///|
test "stable v1 manifest has the exact fixed method names" {
  let methods = acp_v1_method_manifest()
  assert_eq(manifest_method_names(methods), [
    "initialize", "authenticate", "logout", "session/new", "session/load", "session/resume",
    "session/list", "session/delete", "session/close", "session/set_mode", "session/set_config_option",
    "session/prompt", "session/cancel", "session/request_permission", "fs/read_text_file",
    "fs/write_text_file", "terminal/create", "terminal/output", "terminal/wait_for_exit",
    "terminal/kill", "terminal/release", "elicitation/create", "session/update",
    "elicitation/complete", "$/cancel_request",
  ])
}

///|
test "stable v1 manifest records request and notification directions" {
  let methods = acp_v1_method_manifest()
  let mut client_requests = 0
  let mut client_notifications = 0
  let mut agent_requests = 0
  let mut agent_notifications = 0
  let mut bidirectional_notifications = 0
  for entry in methods {
    match (entry.direction, entry.kind) {
      (ClientToAgent, Request) => client_requests += 1
      (ClientToAgent, Notification) => client_notifications += 1
      (AgentToClient, Request) => agent_requests += 1
      (AgentToClient, Notification) => agent_notifications += 1
      (Bidirectional, Notification) => bidirectional_notifications += 1
      _ =>
        fail("manifest contains an impossible request/notification direction")
    }
  }
  assert_eq(client_requests, 12)
  assert_eq(client_notifications, 1)
  assert_eq(agent_requests, 9)
  assert_eq(agent_notifications, 2)
  assert_eq(bidirectional_notifications, 1)
}

///|
test "unstable and v2 overlay names are outside the stable manifest" {
  let methods = acp_v1_method_manifest()
  // Exact-set equality above is the exclusion proof for every name absent from
  // the pinned v1 stable table.  Keep the named v2-only overlay checks here as
  // readable regression guards for the most likely version mix-ups.
  assert_false(manifest_has_name(methods, "auth/login"))
  assert_false(manifest_has_name(methods, "auth/logout"))
}

///|
test "manifest calls return independent arrays" {
  let first = acp_v1_method_manifest()
  let second = acp_v1_method_manifest()
  first.push({
    method_name: "test-only",
    direction: ClientToAgent,
    kind: Request,
  })
  assert_eq(first.length(), second.length() + 1)
  assert_true(manifest_has_name(second, "$/cancel_request"))
}

///|
test "stable manifest cross-checks every direction and kind with closed unions" {
  let methods = acp_v1_method_manifest()
  let mut agent_requests = 0
  let mut agent_notifications = 0
  let mut client_requests = 0
  let mut client_notifications = 0
  let mut bidirectional_notifications = 0
  for entry in methods {
    let params = Some(manifest_test_params(entry.method_name))
    match (entry.direction, entry.kind) {
      (ClientToAgent, Request) => {
        let value = decode_agent_request(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        agent_requests += 1
      }
      (ClientToAgent, Notification) => {
        let value = decode_agent_notification(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        agent_notifications += 1
      }
      (AgentToClient, Request) => {
        let value = decode_client_request(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        client_requests += 1
      }
      (AgentToClient, Notification) => {
        let value = decode_client_notification(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        client_notifications += 1
      }
      (Bidirectional, Notification) => {
        let agent_value = decode_agent_notification(entry.method_name, params)
        let client_value = decode_client_notification(entry.method_name, params)
        assert_eq(agent_value.method_name(), entry.method_name)
        assert_eq(client_value.method_name(), entry.method_name)
        bidirectional_notifications += 1
      }
      _ => fail("manifest direction/kind combination is not supported")
    }
  }
  assert_eq(agent_requests, 12)
  assert_eq(agent_notifications, 1)
  assert_eq(client_requests, 9)
  assert_eq(client_notifications, 2)
  assert_eq(bidirectional_notifications, 1)
}

///|
/// Render one method entry as a sortable exact-set row.  Sorting keeps the
/// drift comparison deterministic regardless of JSON object iteration order.
fn manifest_drift_row(
  method_name : String,
  direction : AcpV1MethodDirection,
  kind : AcpV1MethodKind,
) -> String {
  let direction_text = match direction {
    ClientToAgent => "client->agent"
    AgentToClient => "agent->client"
    Bidirectional => "bidirectional"
  }
  let kind_text = match kind {
    Request => "request"
    Notification => "notification"
  }
  method_name + " " + direction_text + " " + kind_text
}

///|
/// Deterministic insertion sort for exact-set rows; avoids relying on library
/// sort order so both sides of the drift comparison share one total order.
fn manifest_drift_sort_rows(rows : Array[String]) -> Array[String] {
  let sorted : Array[String] = []
  for row in rows {
    sorted.push(row)
    let mut index = sorted.length() - 1
    while index > 0 && sorted[index - 1] > sorted[index] {
      let swap = sorted[index - 1]
      sorted[index - 1] = sorted[index]
      sorted[index] = swap
      index -= 1
    }
  }
  sorted
}

///|
fn manifest_drift_contains(rows : Array[String], wanted : String) -> Bool {
  for row in rows {
    if row == wanted {
      return true
    }
  }
  false
}

///|
/// Parse the pinned v1 `meta.json` into (method name, direction) rows.  The
/// meta groups name the handler side, so `agentMethods` are Client->Agent,
/// `clientMethods` are Agent->Client, and `protocolMethods` are bidirectional.
/// Any deviation from the pinned v1 shape aborts instead of guessing.
fn pinned_v1_meta_rows(meta : Json) -> Array[(String, AcpV1MethodDirection)] {
  let fields = match meta {
    Object(fields) => fields
    _ => abort("pinned v1 meta.json is not a JSON object")
  }
  match fields.get("version") {
    Some(Number(version, ..)) =>
      if version != 1.0 {
        abort("pinned v1 meta.json version is not 1")
      }
    _ => abort("pinned v1 meta.json is missing the numeric version field")
  }
  let rows : Array[(String, AcpV1MethodDirection)] = []
  let groups : Array[(String, AcpV1MethodDirection)] = [
    ("agentMethods", ClientToAgent),
    ("clientMethods", AgentToClient),
    ("protocolMethods", Bidirectional),
  ]
  for group in groups {
    let group_key = group.0
    let direction = group.1
    let entries = match fields.get(group_key) {
      Some(Object(entries)) => entries
      _ => abort("pinned v1 meta.json is missing object group " + group_key)
    }
    entries.each((key, value) => {
      let name = match value {
        String(name) => name
        _ =>
          abort(
            "pinned v1 meta.json group " +
            group_key +
            " entry " +
            key +
            " is not a string",
          )
      }
      rows.push((name, direction))
    })
  }
  let keys : Array[String] = []
  fields.each((key, _value) => keys.push(key))
  if keys.length() != 4 {
    abort(
      "pinned v1 meta.json has unexpected top-level keys; expected exactly version, agentMethods, clientMethods, protocolMethods",
    )
  }
  rows
}

///|
/// Collect every (x-method, x-side) annotation pair from the pinned v1
/// `schema.json` payload definitions.  A def carrying only one of the two
/// annotations aborts: the gate must not guess around annotation drift.
fn pinned_v1_schema_rows(schema : Json) -> Array[(String, String)] {
  let fields = match schema {
    Object(fields) => fields
    _ => abort("pinned v1 schema.json is not a JSON object")
  }
  let defs = match fields.get("$defs") {
    Some(Object(defs)) => defs
    _ => abort("pinned v1 schema.json is missing the $defs object")
  }
  let rows : Array[(String, String)] = []
  defs.each((def_name, def) => {
    match def {
      Object(props) => {
        let method_annotation = props.get("x-method")
        let side_annotation = props.get("x-side")
        match (method_annotation, side_annotation) {
          (Some(String(name)), Some(String(part))) => rows.push((name, part))
          (None, None) => ()
          _ =>
            abort(
              "pinned v1 schema.json def " +
              def_name +
              " has malformed x-method/x-side annotations",
            )
        }
      }
      _ => ()
    }
  })
  rows
}

///|
fn pinned_v1_unique_names(rows : Array[(String, String)]) -> Array[String] {
  let names : Array[String] = []
  for row in rows {
    if !manifest_drift_contains(names, row.0) {
      names.push(row.0)
    }
  }
  names
}

///|
/// The unique x-side recorded for one method across its annotated payload
/// definitions; conflicting sides or a method missing from the schema abort.
fn pinned_v1_schema_side(
  rows : Array[(String, String)],
  name : String,
) -> String {
  let mut side = ""
  let mut seen = false
  for row in rows {
    if row.0 == name {
      if seen && side != row.1 {
        abort(
          "pinned v1 schema.json method " +
          name +
          " has conflicting x-side values",
        )
      }
      side = row.1
      seen = true
    }
  }
  if !seen {
    abort(
      "pinned v1 meta.json method " +
      name +
      " has no x-method annotation in schema.json",
    )
  }
  side
}

///|
fn pinned_v1_schema_def_count(
  rows : Array[(String, String)],
  name : String,
) -> Int {
  let mut count = 0
  for row in rows {
    if row.0 == name {
      count += 1
    }
  }
  count
}

///|
/// Map the schema handler-side annotation onto the manifest direction.
fn pinned_v1_direction_from_side(
  name : String,
  side : String,
) -> AcpV1MethodDirection {
  match side {
    "agent" => ClientToAgent
    "client" => AgentToClient
    "protocol" => Bidirectional
    _ =>
      abort(
        "pinned v1 schema.json method " + name + " has unknown x-side " + side,
      )
  }
}

///|
/// Derive the wire kind from the pinned bytes: a request method carries one
/// annotated request payload def plus one response payload def, while a
/// notification carries exactly one annotated payload def.  Any other count
/// aborts so annotation drift cannot be silently absorbed.
fn pinned_v1_kind_from_count(name : String, count : Int) -> AcpV1MethodKind {
  match count {
    1 => Notification
    2 => Request
    _ =>
      abort(
        "pinned v1 schema.json method " +
        name +
        " has " +
        count.to_string() +
        " annotated payload defs; expected 1 (notification) or 2 (request plus response)",
      )
  }
}

///|
/// Exact-set drift gate against the pinned v1 bytes landed at
/// `spec/schema/v1/meta.json` and `spec/schema/v1/schema.json` under the
/// `spec/LOCK.md` pin.  The expected method set is derived entirely from the
/// pinned files (names and directions from the meta groups, kinds from the
/// schema's x-method/x-side annotated payload-def cardinality), never from
/// the hand-written manifest, and both sources must agree with each other
/// before the manifest comparison runs.
async test "stable v1 manifest is the exact method set of the pinned v1 schema and meta bytes" {
  let meta = @fs.read_file("spec/schema/v1/meta.json").json()
  let schema = @fs.read_file("spec/schema/v1/schema.json").json()
  let meta_rows = pinned_v1_meta_rows(meta)
  let schema_rows = pinned_v1_schema_rows(schema)
  let schema_names = pinned_v1_unique_names(schema_rows)
  let meta_names : Array[String] = []
  for row in meta_rows {
    meta_names.push(row.0)
  }
  if schema_names.length() != meta_names.length() {
    abort(
      "pinned v1 schema.json and meta.json disagree on the method name set size",
    )
  }
  for name in meta_names {
    if !manifest_drift_contains(schema_names, name) {
      abort(
        "pinned v1 meta.json method " +
        name +
        " has no x-method annotation in schema.json",
      )
    }
  }
  let expected : Array[String] = []
  for row in meta_rows {
    let name = row.0
    let group_direction = row.1
    let side = pinned_v1_schema_side(schema_rows, name)
    let side_direction = pinned_v1_direction_from_side(name, side)
    if group_direction != side_direction {
      abort(
        "pinned v1 method " + name + " meta group and schema x-side disagree",
      )
    }
    let count = pinned_v1_schema_def_count(schema_rows, name)
    let kind = pinned_v1_kind_from_count(name, count)
    expected.push(manifest_drift_row(name, side_direction, kind))
  }
  let actual : Array[String] = []
  for entry in acp_v1_method_manifest() {
    actual.push(
      manifest_drift_row(entry.method_name, entry.direction, entry.kind),
    )
  }
  assert_eq(
    manifest_drift_sort_rows(expected),
    manifest_drift_sort_rows(actual),
  )
}

///|
/// Membership gate for the unstable overlay: the pinned v1
/// `meta.unstable.json` bytes (vendored, same four-key shape as the stable
/// `meta.json`) must list `session/fork` among the Agent-handled methods, the
/// unstable manifest must be exactly `[session/fork]` with the
/// ClientToAgent/Request direction and kind, and the stable manifest must keep
/// excluding it.  Any shape deviation aborts instead of guessing, reusing the
/// stable pinned-meta parser's defensive rules.
async test "unstable v1 manifest is a session/fork subset of the vendored unstable meta" {
  let meta = @fs.read_file("spec/schema/v1/meta.unstable.json").json()
  let unstable_agent_names : Array[String] = []
  for row in pinned_v1_meta_rows(meta) {
    // The meta groups name the handler side, so `agentMethods` rows are the
    // Client->Agent entries.
    if row.1 is ClientToAgent {
      unstable_agent_names.push(row.0)
    }
  }
  if unstable_agent_names.is_empty() {
    abort("pinned v1 meta.unstable.json lists no agent methods")
  }
  if !manifest_drift_contains(unstable_agent_names, "session/fork") {
    abort(
      "pinned v1 meta.unstable.json does not list session/fork among its agent methods",
    )
  }
  let unstable_methods = acp_v1_unstable_method_manifest()
  assert_eq(manifest_method_names(unstable_methods), ["session/fork"])
  for entry in unstable_methods {
    match (entry.direction, entry.kind) {
      (ClientToAgent, Request) => {
        let value = decode_agent_request(
          entry.method_name,
          Some(manifest_test_params(entry.method_name)),
        )
        assert_eq(value.method_name(), entry.method_name)
      }
      _ => fail("unstable manifest direction/kind combination is not supported")
    }
  }
  assert_false(manifest_has_name(acp_v1_method_manifest(), "session/fork"))
}

///|
/// ASCII lowercase code of one character, for case-insensitive scanning.
fn manifest_boundary_char_code(ch : Char) -> Int {
  let code = ch.to_int()
  if code >= 65 && code <= 90 {
    code + 32
  } else {
    code
  }
}

///|
/// Case-insensitive substring scan over package manifest text.
fn manifest_boundary_contains_ci(text : String, needle : String) -> Bool {
  let hay : Array[Char] = []
  for ch in text {
    hay.push(ch)
  }
  let pattern : Array[Char] = []
  for ch in needle {
    pattern.push(ch)
  }
  let pattern_length = pattern.length()
  if pattern_length == 0 {
    return true
  }
  let last = hay.length() - pattern_length
  let mut start = 0
  let mut found = false
  while start <= last && !found {
    let mut offset = 0
    let mut equal = true
    while offset < pattern_length && equal {
      let left = manifest_boundary_char_code(hay[start + offset])
      let right = manifest_boundary_char_code(pattern[offset])
      if left != right {
        equal = false
      } else {
        offset += 1
      }
    }
    if equal {
      found = true
    }
    start += 1
  }
  found
}

///|
/// Canonicalize one walked path: `@fs.walk` prefixes subdirectories of the
/// "." root with "./", so strip that prefix to get plain relative paths.
fn manifest_boundary_strip_dot_slash(path : String) -> String {
  let chars : Array[Char] = []
  for ch in path {
    chars.push(ch)
  }
  if chars.length() >= 2 && chars[0] == '.' && chars[1] == '/' {
    let out = StringBuilder::new()
    let mut index = 2
    while index < chars.length() {
      out.write_char(chars[index])
      index += 1
    }
    out.to_string()
  } else {
    path
  }
}

///|
/// Read one package manifest file for the boundary gate.  A failed read is
/// recorded as a violation so the gate fails loudly instead of skipping the
/// file; the empty text is never inspected further.
async fn manifest_boundary_read(
  path : String,
  violations : Array[String],
) -> String {
  @fs.read_file(path).text() catch {
    _ => {
      violations.push("cannot read package file " + path)
      ""
    }
  }
}

///|
/// Structural release-boundary drift gate, provable at test time: walk the
/// repository package graph and assert (a) no `moon.mod`/`moon.pkg` in either
/// release facade or any implementation package references a Posoco package,
/// and (b) the root stable facade does not import the `experimental` facade.
/// The required-file list keeps the gate honest: if the walk starts anywhere
/// other than the module root, it aborts instead of passing vacuously.
async test "release boundary: no posoco dependency anywhere and no experimental import in the root facade" {
  let checked : Array[String] = []
  let violations : Array[String] = []
  @fs.walk(
    ".",
    (dir, files) => {
      for file in files {
        let is_manifest = file == "moon.pkg" ||
          file == "moon.mod" ||
          file == "moon.pkg.json" ||
          file == "moon.mod.json"
        if is_manifest {
          let path = if dir == "." {
            file
          } else {
            manifest_boundary_strip_dot_slash(dir + "/" + file)
          }
          let text = manifest_boundary_read(path, violations)
          if manifest_boundary_contains_ci(text, "posoco") {
            violations.push(path + " references a Posoco package")
          }
          if dir == "." &&
            file == "moon.pkg" &&
            manifest_boundary_contains_ci(text, "experimental") {
            violations.push(
              "root facade moon.pkg references the experimental facade",
            )
          }
          checked.push(path)
        }
      }
    },
    exclude=path => {
      path == "./_build" ||
      path == "./.mooncakes" ||
      path == "./.git" ||
      path == "./target" ||
      path == "./.moonagent" ||
      path == "./node_modules"
    },
  )
  for
    required in [
      "moon.mod", "moon.pkg", "experimental/moon.pkg", "method/moon.pkg",
    ] {
    if !manifest_drift_contains(checked, required) {
      abort(
        "release boundary gate did not inspect " +
        required +
        "; the test cwd is not the module root",
      )
    }
  }
  if checked.length() < 10 {
    abort(
      "release boundary gate inspected only " +
      checked.length().to_string() +
      " package files",
    )
  }
  assert_eq(violations, [])
}
