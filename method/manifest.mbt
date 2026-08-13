///|
/// The endpoint direction of a stable ACP v1 JSON-RPC method.
pub(all) enum AcpV1MethodDirection {
  ClientToAgent
  AgentToClient
  Bidirectional
} derive(Eq, Debug)

///|
/// Whether a stable ACP v1 method expects a response.
pub(all) enum AcpV1MethodKind {
  Request
  Notification
} derive(Eq, Debug)

///|
/// One entry in the stable ACP v1 method manifest.
///
/// `method_name` is the exact JSON-RPC wire name.  The direction and kind are
/// protocol facts, not runtime capability decisions; capability gates are
/// applied by the endpoint layer after method lookup.
pub(all) struct AcpV1Method {
  method_name : String
  direction : AcpV1MethodDirection
  kind : AcpV1MethodKind
} derive(Eq, Debug)

///|
/// Return a fresh, exact manifest for the stable ACP v1 method surface.
///
/// A fresh array on every call keeps the public value free of shared mutable
/// state.  This list follows the fixed v1 table in the implementation plan;
/// v2 and unstable overlays are deliberately absent.
pub fn acp_v1_method_manifest() -> Array[AcpV1Method] {
  [
    // Client -> Agent requests.
    { method_name: "initialize", direction: ClientToAgent, kind: Request },
    { method_name: "authenticate", direction: ClientToAgent, kind: Request },
    { method_name: "logout", direction: ClientToAgent, kind: Request },
    { method_name: "session/new", direction: ClientToAgent, kind: Request },
    { method_name: "session/load", direction: ClientToAgent, kind: Request },
    { method_name: "session/resume", direction: ClientToAgent, kind: Request },
    { method_name: "session/list", direction: ClientToAgent, kind: Request },
    { method_name: "session/delete", direction: ClientToAgent, kind: Request },
    { method_name: "session/close", direction: ClientToAgent, kind: Request },
    { method_name: "session/set_mode", direction: ClientToAgent, kind: Request },
    {
      method_name: "session/set_config_option",
      direction: ClientToAgent,
      kind: Request,
    },
    { method_name: "session/prompt", direction: ClientToAgent, kind: Request },
    // Client -> Agent notification.
    {
      method_name: "session/cancel",
      direction: ClientToAgent,
      kind: Notification,
    },
    // Agent -> Client requests.
    {
      method_name: "session/request_permission",
      direction: AgentToClient,
      kind: Request,
    },
    {
      method_name: "fs/read_text_file",
      direction: AgentToClient,
      kind: Request,
    },
    {
      method_name: "fs/write_text_file",
      direction: AgentToClient,
      kind: Request,
    },
    { method_name: "terminal/create", direction: AgentToClient, kind: Request },
    { method_name: "terminal/output", direction: AgentToClient, kind: Request },
    {
      method_name: "terminal/wait_for_exit",
      direction: AgentToClient,
      kind: Request,
    },
    { method_name: "terminal/kill", direction: AgentToClient, kind: Request },
    { method_name: "terminal/release", direction: AgentToClient, kind: Request },
    {
      method_name: "elicitation/create",
      direction: AgentToClient,
      kind: Request,
    },
    // Agent -> Client notifications.
    {
      method_name: "session/update",
      direction: AgentToClient,
      kind: Notification,
    },
    {
      method_name: "elicitation/complete",
      direction: AgentToClient,
      kind: Notification,
    },
    // This protocol notification can be sent by either endpoint.
    {
      method_name: "$/cancel_request",
      direction: Bidirectional,
      kind: Notification,
    },
  ]
}
