///|
fn manifest_method_names(
  methods : Array[ExperimentalV2Method],
) -> Array[String] {
  let names : Array[String] = []
  for entry in methods {
    names.push(entry.method_name)
  }
  names
}

///|
fn manifest_has_name(
  methods : Array[ExperimentalV2Method],
  wanted : String,
) -> Bool {
  for entry in methods {
    if entry.method_name == wanted {
      return true
    }
  }
  false
}

///|
test "v2 manifest has the exact fixed method names" {
  let methods = experimental_v2_method_manifest()
  assert_eq(manifest_method_names(methods), [
    "initialize", "auth/login", "auth/logout", "session/new", "session/prompt", "session/list",
    "session/delete", "session/resume", "session/close", "session/set_config_option",
    "session/cancel", "session/request_permission", "elicitation/create", "session/update",
    "elicitation/complete", "$/cancel_request",
  ])
}

///|
test "v2 manifest records request and notification directions" {
  let methods = experimental_v2_method_manifest()
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
  assert_eq(client_requests, 10)
  assert_eq(client_notifications, 1)
  assert_eq(agent_requests, 2)
  assert_eq(agent_notifications, 2)
  assert_eq(bidirectional_notifications, 1)
}

///|
test "v1-only and unstable overlay names are outside the v2 manifest" {
  let methods = experimental_v2_method_manifest()
  // Exact-set equality above is the exclusion proof for every absent name.
  // Keep the named checks as readable regression guards for the most likely
  // version mix-ups: v1-only methods and unstable-overlay methods.
  for
    v1_only in [
      "authenticate", "logout", "session/load", "session/set_mode", "fs/read_text_file",
      "terminal/create",
    ] {
    assert_false(manifest_has_name(methods, v1_only))
  }
  for
    unstable_only in [
      "session/fork", "mcp/message", "mcp/connect", "providers/list", "document/didOpen",
      "nes/start",
    ] {
    assert_false(manifest_has_name(methods, unstable_only))
  }
}

///|
test "v2 manifest calls return independent arrays" {
  let first = experimental_v2_method_manifest()
  let second = experimental_v2_method_manifest()
  first.push({
    method_name: "test-only",
    direction: ClientToAgent,
    kind: Request,
  })
  assert_eq(first.length(), second.length() + 1)
  assert_true(manifest_has_name(second, "$/cancel_request"))
}

///|
/// Render one method entry as a sortable exact-set row.
fn manifest_drift_row(
  method_name : String,
  direction : ExperimentalV2MethodDirection,
  kind : ExperimentalV2MethodKind,
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
/// Deterministic insertion sort so both sides of the drift comparison share
/// one total order regardless of JSON object iteration order.
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
/// Parse the pinned v2 `meta.json` into (method name, direction) rows.  The
/// meta groups name the handler side, so `agentMethods` are Client->Agent,
/// `clientMethods` are Agent->Client, and `protocolMethods` are bidirectional.
/// Any deviation from the pinned v2 shape aborts instead of guessing.
fn pinned_v2_meta_rows(
  meta : Json,
) -> Array[(String, ExperimentalV2MethodDirection)] {
  let fields = match meta {
    Object(fields) => fields
    _ => abort("pinned v2 meta.json is not a JSON object")
  }
  match fields.get("version") {
    Some(Number(version, ..)) =>
      if version != 2.0 {
        abort("pinned v2 meta.json version is not 2")
      }
    _ => abort("pinned v2 meta.json is missing the numeric version field")
  }
  let rows : Array[(String, ExperimentalV2MethodDirection)] = []
  let groups : Array[(String, ExperimentalV2MethodDirection)] = [
    ("agentMethods", ClientToAgent),
    ("clientMethods", AgentToClient),
    ("protocolMethods", Bidirectional),
  ]
  for group in groups {
    let group_key = group.0
    let direction = group.1
    let entries = match fields.get(group_key) {
      Some(Object(entries)) => entries
      _ => abort("pinned v2 meta.json is missing object group " + group_key)
    }
    entries.each((key, value) => {
      let name = match value {
        String(name) => name
        _ =>
          abort(
            "pinned v2 meta.json group " +
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
      "pinned v2 meta.json has unexpected top-level keys; expected exactly version, agentMethods, clientMethods, protocolMethods",
    )
  }
  rows
}

///|
/// Collect every (x-method, x-side) annotation pair from the pinned v2
/// `schema.json` payload definitions.  A def carrying only one of the two
/// annotations aborts: the gate must not guess around annotation drift.
fn pinned_v2_schema_rows(schema : Json) -> Array[(String, String)] {
  let fields = match schema {
    Object(fields) => fields
    _ => abort("pinned v2 schema.json is not a JSON object")
  }
  let defs = match fields.get("$defs") {
    Some(Object(defs)) => defs
    _ => abort("pinned v2 schema.json is missing the $defs object")
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
              "pinned v2 schema.json def " +
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
fn pinned_v2_unique_names(rows : Array[(String, String)]) -> Array[String] {
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
fn pinned_v2_schema_side(
  rows : Array[(String, String)],
  name : String,
) -> String {
  let mut side = ""
  let mut seen = false
  for row in rows {
    if row.0 == name {
      if seen && side != row.1 {
        abort(
          "pinned v2 schema.json method " +
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
      "pinned v2 meta.json method " +
      name +
      " has no x-method annotation in schema.json",
    )
  }
  side
}

///|
fn pinned_v2_schema_def_count(
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
fn pinned_v2_direction_from_side(
  name : String,
  side : String,
) -> ExperimentalV2MethodDirection {
  match side {
    "agent" => ClientToAgent
    "client" => AgentToClient
    "protocol" => Bidirectional
    _ =>
      abort(
        "pinned v2 schema.json method " + name + " has unknown x-side " + side,
      )
  }
}

///|
/// Derive the wire kind from the pinned bytes: a request method carries one
/// annotated request payload def plus one response payload def, while a
/// notification carries exactly one annotated payload def.  Any other count
/// aborts so annotation drift cannot be silently absorbed.
fn pinned_v2_kind_from_count(
  name : String,
  count : Int,
) -> ExperimentalV2MethodKind {
  match count {
    1 => Notification
    2 => Request
    _ =>
      abort(
        "pinned v2 schema.json method " +
        name +
        " has " +
        count.to_string() +
        " annotated payload defs; expected 1 (notification) or 2 (request plus response)",
      )
  }
}

///|
/// Exact-set drift gate against the pinned v2 bytes landed at
/// `spec/schema/v2/meta.json` and `spec/schema/v2/schema.json` under the
/// `spec/LOCK.md` pin.  The expected method set is derived entirely from the
/// pinned files (names and directions from the meta groups, kinds from the
/// schema's x-method/x-side annotated payload-def cardinality), never from
/// the hand-written manifest, and both sources must agree with each other
/// before the manifest comparison runs.
async test "v2 manifest is the exact method set of the pinned v2 schema and meta bytes" {
  let meta = @fs.read_file("spec/schema/v2/meta.json").json()
  let schema = @fs.read_file("spec/schema/v2/schema.json").json()
  let meta_rows = pinned_v2_meta_rows(meta)
  let schema_rows = pinned_v2_schema_rows(schema)
  let schema_names = pinned_v2_unique_names(schema_rows)
  let meta_names : Array[String] = []
  for row in meta_rows {
    meta_names.push(row.0)
  }
  if schema_names.length() != meta_names.length() {
    abort(
      "pinned v2 schema.json and meta.json disagree on the method name set size",
    )
  }
  for name in meta_names {
    if !manifest_drift_contains(schema_names, name) {
      abort(
        "pinned v2 meta.json method " +
        name +
        " has no x-method annotation in schema.json",
      )
    }
  }
  let expected : Array[String] = []
  for row in meta_rows {
    let name = row.0
    let group_direction = row.1
    let side = pinned_v2_schema_side(schema_rows, name)
    let side_direction = pinned_v2_direction_from_side(name, side)
    if group_direction != side_direction {
      abort(
        "pinned v2 method " + name + " meta group and schema x-side disagree",
      )
    }
    let count = pinned_v2_schema_def_count(schema_rows, name)
    let kind = pinned_v2_kind_from_count(name, count)
    expected.push(manifest_drift_row(name, side_direction, kind))
  }
  let actual : Array[String] = []
  for entry in experimental_v2_method_manifest() {
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
/// Membership gate for the unstable overlay: the pinned v2
/// `meta.unstable.json` bytes (vendored, same four-key shape as the stable
/// `meta.json`) must list `session/fork` among the Agent-handled methods, the
/// unstable manifest must be exactly `[session/fork]`, and the stable
/// manifest must keep excluding it.  Any shape deviation aborts instead of
/// guessing, reusing the stable pinned-meta parser's defensive rules.
async test "v2 unstable manifest is a deliberate session/fork subset of the pinned unstable meta bytes" {
  let meta = @fs.read_file("spec/schema/v2/meta.unstable.json").json()
  let unstable_agent_names : Array[String] = []
  for row in pinned_v2_meta_rows(meta) {
    // The meta groups name the handler side, so `agentMethods` rows are the
    // Client->Agent entries.
    if row.1 is ClientToAgent {
      unstable_agent_names.push(row.0)
    }
  }
  if unstable_agent_names.is_empty() {
    abort("pinned v2 meta.unstable.json lists no agent methods")
  }
  if !manifest_drift_contains(unstable_agent_names, "session/fork") {
    abort(
      "pinned v2 meta.unstable.json does not list session/fork among its agent methods",
    )
  }
  assert_eq(manifest_method_names(experimental_v2_unstable_method_manifest()), [
    "session/fork",
  ])
  assert_false(
    manifest_has_name(experimental_v2_method_manifest(), "session/fork"),
  )
}
