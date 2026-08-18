///|
/// Known payload of an `AuthMethod` with the `type: "agent"` discriminator:
/// the Agent handles authentication itself through `auth/login`.
pub(all) struct ExperimentalV2AuthMethodAgent {
  method_id : String
  name : String
  description : String?
  meta : Json?
} derive(Eq, Debug)

///|
/// One advertised authentication method.  The schema has an open fallback:
/// `_`-prefixed and unknown types stay as `Extension`/`Future` raw payloads.
pub type ExperimentalV2AuthMethod = ExperimentalV2Open[
  ExperimentalV2AuthMethodAgent,
]

///|
pub fn experimental_v2_decode_auth_method(
  value : Json,
  path? : String = "authMethod",
) -> ExperimentalV2AuthMethod raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["agent"],
    (_, payload) => {
      let fields = experimental_v2_require_object(payload, path~)
      experimental_v2_reject_unknown(
        fields,
        ["type", "methodId", "name", "description", "_meta"],
        prefix=path,
      )
      let method_id = experimental_v2_validate_id(
        experimental_v2_decode_string(
          experimental_v2_required(fields, "methodId", path=path + ".methodId"),
          path=path + ".methodId",
        ),
        field_path=path + ".methodId",
      )
      let name = experimental_v2_decode_string(
        experimental_v2_required(fields, "name", path=path + ".name"),
        path=path + ".name",
      )
      let description = experimental_v2_decode_optional(
        fields,
        "description",
        path=path + ".description",
        (value, path) => experimental_v2_decode_string(value, path~),
      )
      let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
      { method_id, name, description, meta }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_auth_method(
  value : ExperimentalV2AuthMethod,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    let fields : Map[String, Json] = Map([])
    fields["type"] = Json::string("agent")
    fields["methodId"] = Json::string(known.method_id)
    fields["name"] = Json::string(known.name)
    experimental_v2_put_optional(fields, "description", known.description, value => {
      Json::string(value)
    })
    experimental_v2_put_meta(fields, known.meta)
    Json::object(fields)
  })
}

///|
fn experimental_v2_decode_auth_methods(
  value : Json,
  path~ : String,
) -> Array[ExperimentalV2AuthMethod] raise ExperimentalV2DecodeError {
  experimental_v2_decode_array(value, path~, (item, item_path) => {
    experimental_v2_decode_auth_method(item, path=item_path)
  })
}

///|
fn experimental_v2_encode_auth_methods(
  values : Array[ExperimentalV2AuthMethod],
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_array(values, experimental_v2_encode_auth_method)
}

///|
/// Parameters of `auth/login`.
pub(all) struct ExperimentalV2LoginParams {
  method_id : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_login_params(
  value : Json,
  path? : String = "auth/login",
) -> ExperimentalV2LoginParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta", "methodId"], prefix=path)
  let method_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "methodId", path=path + ".methodId"),
      path=path + ".methodId",
    ),
    field_path=path + ".methodId",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { method_id, meta }
}

///|
pub fn experimental_v2_encode_login_params(
  value : ExperimentalV2LoginParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["methodId"] = Json::string(value.method_id)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `auth/login`; it carries only protocol metadata.
pub(all) struct ExperimentalV2LoginResult {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_login_result(
  value : Json,
  path? : String = "auth/login",
) -> ExperimentalV2LoginResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta") }
}

///|
pub fn experimental_v2_encode_login_result(
  value : ExperimentalV2LoginResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Parameters of `auth/logout`; it carries only protocol metadata.
pub(all) struct ExperimentalV2LogoutParams {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_logout_params(
  value : Json,
  path? : String = "auth/logout",
) -> ExperimentalV2LogoutParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta") }
}

///|
pub fn experimental_v2_encode_logout_params(
  value : ExperimentalV2LogoutParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `auth/logout`; it carries only protocol metadata.
pub(all) struct ExperimentalV2LogoutResult {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_logout_result(
  value : Json,
  path? : String = "auth/logout",
) -> ExperimentalV2LogoutResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta") }
}

///|
pub fn experimental_v2_encode_logout_result(
  value : ExperimentalV2LogoutResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
