///|
/// The endpoint direction of an ACP v2 stable-baseline JSON-RPC method.
pub(all) enum ExperimentalV2MethodDirection {
  ClientToAgent
  AgentToClient
  Bidirectional
} derive(Eq, Debug)

///|
/// Whether an ACP v2 stable-baseline method expects a response.
pub(all) enum ExperimentalV2MethodKind {
  Request
  Notification
} derive(Eq, Debug)

///|
/// One entry in the ACP v2 stable-baseline method manifest.
///
/// `method_name` is the exact JSON-RPC wire name.  Direction and kind are
/// protocol facts pinned by `spec/LOCK.md`; capability gates are applied by
/// the endpoint layer after method lookup.
pub(all) struct ExperimentalV2Method {
  method_name : String
  direction : ExperimentalV2MethodDirection
  kind : ExperimentalV2MethodKind
} derive(Eq, Debug)

///|
/// Return a fresh, exact manifest for the v2 stable-baseline method surface.
///
/// A fresh array on every call keeps the public value free of shared mutable
/// state.  Unstable overlay names and v1-only names are deliberately absent.
pub fn experimental_v2_method_manifest() -> Array[ExperimentalV2Method] {
  [
    // Client -> Agent requests.
    { method_name: "initialize", direction: ClientToAgent, kind: Request, },
    { method_name: "auth/login", direction: ClientToAgent, kind: Request, },
    { method_name: "auth/logout", direction: ClientToAgent, kind: Request, },
    { method_name: "session/new", direction: ClientToAgent, kind: Request, },
    { method_name: "session/prompt", direction: ClientToAgent, kind: Request, },
    { method_name: "session/list", direction: ClientToAgent, kind: Request, },
    { method_name: "session/delete", direction: ClientToAgent, kind: Request, },
    { method_name: "session/resume", direction: ClientToAgent, kind: Request, },
    { method_name: "session/close", direction: ClientToAgent, kind: Request, },
    {
      method_name: "session/set_config_option",
      direction: ClientToAgent,
      kind: Request,
    },
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

///|
/// Return a fresh manifest for the v2 unstable-overlay method surface this
/// facade mirrors.  Upstream unstable (RFD session-fork, Draft).
///
/// This is a **deliberate subset** of the pinned v2 unstable overlay
/// (`spec/schema/v2/meta.unstable.json`, vendored): only `session/fork` is
/// implemented.  The stable manifest above deliberately excludes every
/// unstable name, and its exact-set drift gate against the pinned stable
/// `meta.json`/`schema.json` bytes is unchanged by this overlay.
pub fn experimental_v2_unstable_method_manifest() -> Array[ExperimentalV2Method] {
  [{ method_name: "session/fork", direction: ClientToAgent, kind: Request, }]
}
