///|
/// Semantic category of a session configuration option.  The schema has an
/// open fallback: `_`-prefixed categories are implementation extensions and
/// unknown others are future ACP values.
pub(all) enum ExperimentalV2ConfigCategory {
  CategoryMode
  CategoryModel
  CategoryModelConfig
  CategoryThoughtLevel
  CategoryExtension(tag~ : String)
  CategoryFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_config_category(
  value : Json,
  path? : String = "category",
) -> ExperimentalV2ConfigCategory raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "mode" => CategoryMode
    "model" => CategoryModel
    "model_config" => CategoryModelConfig
    "thought_level" => CategoryThoughtLevel
    _ =>
      if tag.has_prefix("_") {
        CategoryExtension(tag~)
      } else {
        CategoryFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_config_category(
  value : ExperimentalV2ConfigCategory,
) -> Json {
  match value {
    CategoryMode => Json::string("mode")
    CategoryModel => Json::string("model")
    CategoryModelConfig => Json::string("model_config")
    CategoryThoughtLevel => Json::string("thought_level")
    CategoryExtension(tag~) => Json::string(tag)
    CategoryFuture(raw~) => Json::string(raw)
  }
}

///|
/// One selectable value of a session configuration option.
pub(all) struct ExperimentalV2ConfigSelectOption {
  value : String
  name : String
  description : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_config_select_option(
  value : Json,
  path? : String = "selectOption",
) -> ExperimentalV2ConfigSelectOption raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "value", "name", "description"],
    prefix=path,
  )
  let option_value = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "value", path=path + ".value"),
      path=path + ".value",
    ),
    field_path=path + ".value",
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
  { value: option_value, name, description, meta, }
}

///|
pub fn experimental_v2_encode_config_select_option(
  value : ExperimentalV2ConfigSelectOption,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["value"] = Json::string(value.value)
  fields["name"] = Json::string(value.name)
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// One group of selectable values under a shared header.
pub(all) struct ExperimentalV2ConfigSelectGroup {
  group_id : String
  name : String
  options : Array[ExperimentalV2ConfigSelectOption]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_config_select_group(
  value : Json,
  path? : String = "selectGroup",
) -> ExperimentalV2ConfigSelectGroup raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "groupId", "name", "options"],
    prefix=path,
  )
  let group_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "groupId", path=path + ".groupId"),
      path=path + ".groupId",
    ),
    field_path=path + ".groupId",
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let options = experimental_v2_decode_array(
    experimental_v2_required(fields, "options", path=path + ".options"),
    path=path + ".options",
    (item, item_path) => {
      experimental_v2_decode_config_select_option(item, path=item_path)
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { group_id, name, options, meta, }
}

///|
pub fn experimental_v2_encode_config_select_group(
  value : ExperimentalV2ConfigSelectGroup,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["groupId"] = Json::string(value.group_id)
  fields["name"] = Json::string(value.name)
  fields["options"] = experimental_v2_encode_array(
    value.options,
    experimental_v2_encode_config_select_option,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Selectable values of a session configuration option: a flat list or a list
/// of groups.  An empty list is ungrouped, matching the schema's first
/// `anyOf` branch.
pub(all) enum ExperimentalV2ConfigSelectOptions {
  OptionsUngrouped(Array[ExperimentalV2ConfigSelectOption])
  OptionsGrouped(Array[ExperimentalV2ConfigSelectGroup])
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_config_select_options(
  value : Json,
  path? : String = "options",
) -> ExperimentalV2ConfigSelectOptions raise ExperimentalV2DecodeError {
  let items = experimental_v2_require_array(value, path~)
  if items.length() == 0 {
    OptionsUngrouped([])
  } else {
    match items[0] {
      Object(first) =>
        if first.get("value") is Some(_) {
          OptionsUngrouped(
            experimental_v2_decode_array(value, path~, (item, item_path) => {
              experimental_v2_decode_config_select_option(item, path=item_path)
            }),
          )
        } else if first.get("groupId") is Some(_) {
          OptionsGrouped(
            experimental_v2_decode_array(value, path~, (item, item_path) => {
              experimental_v2_decode_config_select_group(item, path=item_path)
            }),
          )
        } else {
          raise InvalidField(
            path=path + "[0]",
            reason="select options must be option values or groups",
          )
        }
      _ =>
        raise InvalidField(
          path=path + "[0]",
          reason="select options must be option values or groups",
        )
    }
  }
}

///|
pub fn experimental_v2_encode_config_select_options(
  value : ExperimentalV2ConfigSelectOptions,
) -> Json raise ExperimentalV2DecodeError {
  match value {
    OptionsUngrouped(options) =>
      experimental_v2_encode_array(
        options, experimental_v2_encode_config_select_option,
      )
    OptionsGrouped(groups) =>
      experimental_v2_encode_array(
        groups, experimental_v2_encode_config_select_group,
      )
  }
}

///|
/// Select payload of a session configuration option; its fields live flat on
/// the option object next to the shared selector fields.
pub(all) struct ExperimentalV2ConfigSelect {
  current_value : String
  options : ExperimentalV2ConfigSelectOptions
} derive(Eq, Debug)

///|
/// Boolean payload of a session configuration option; its field lives flat on
/// the option object.
pub(all) struct ExperimentalV2ConfigBoolean {
  current_value : Bool
} derive(Eq, Debug)

///|
/// Payload of a known session configuration option: `type: "select"` or
/// `type: "boolean"`.
pub(all) enum ExperimentalV2ConfigPayload {
  PayloadSelect(ExperimentalV2ConfigSelect)
  PayloadBoolean(ExperimentalV2ConfigBoolean)
} derive(Eq, Debug)

///|
/// Known shape of a session configuration option, shared by the `select` and
/// `boolean` variants.
pub(all) struct ExperimentalV2SessionConfigOptionKnown {
  config_id : String
  name : String
  description : String?
  category : ExperimentalV2ConfigCategory?
  payload : ExperimentalV2ConfigPayload
  meta : Json?
} derive(Eq, Debug)

///|
/// One session configuration option selector with its current state.  The
/// schema has an open fallback, so unknown option types stay as
/// `Extension`/`Future` raw payloads.
pub type ExperimentalV2SessionConfigOption = ExperimentalV2Open[
  ExperimentalV2SessionConfigOptionKnown,
]

///|
pub fn experimental_v2_decode_config_option(
  value : Json,
  path? : String = "configOption",
) -> ExperimentalV2SessionConfigOption raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["select", "boolean"],
    (tag, payload) => {
      let fields = experimental_v2_require_object(payload, path~)
      let config_id = experimental_v2_validate_id(
        experimental_v2_decode_string(
          experimental_v2_required(fields, "configId", path=path + ".configId"),
          path=path + ".configId",
        ),
        field_path=path + ".configId",
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
      let category = experimental_v2_decode_optional(
        fields,
        "category",
        path=path + ".category",
        (value, path) => experimental_v2_decode_config_category(value, path~),
      )
      let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
      let payload : ExperimentalV2ConfigPayload = match tag {
        "select" => {
          experimental_v2_reject_unknown(
            fields,
            [
              "type", "configId", "name", "description", "category", "_meta", "currentValue",
              "options",
            ],
            prefix=path,
          )
          let current_value = experimental_v2_validate_id(
            experimental_v2_decode_string(
              experimental_v2_required(
                fields,
                "currentValue",
                path=path + ".currentValue",
              ),
              path=path + ".currentValue",
            ),
            field_path=path + ".currentValue",
          )
          let options = experimental_v2_decode_config_select_options(
            experimental_v2_required(fields, "options", path=path + ".options"),
            path=path + ".options",
          )
          PayloadSelect({ current_value, options, })
        }
        _ => {
          experimental_v2_reject_unknown(
            fields,
            [
              "type", "configId", "name", "description", "category", "_meta", "currentValue",
            ],
            prefix=path,
          )
          PayloadBoolean({
            current_value: experimental_v2_decode_boolean(
              experimental_v2_required(
                fields,
                "currentValue",
                path=path + ".currentValue",
              ),
              path=path + ".currentValue",
            ),
          })
        }
      }
      { config_id, name, description, category, payload, meta, }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_config_option(
  value : ExperimentalV2SessionConfigOption,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    let fields : Map[String, Json] = Map([])
    fields["configId"] = Json::string(known.config_id)
    fields["name"] = Json::string(known.name)
    experimental_v2_put_optional(fields, "description", known.description, value => {
      Json::string(value)
    })
    experimental_v2_put_optional(fields, "category", known.category, category => {
      experimental_v2_encode_config_category(category)
    })
    match known.payload {
      PayloadSelect(select) => {
        fields["type"] = Json::string("select")
        fields["currentValue"] = Json::string(select.current_value)
        fields["options"] = experimental_v2_encode_config_select_options(
          select.options,
        )
      }
      PayloadBoolean(boolean) => {
        fields["type"] = Json::string("boolean")
        fields["currentValue"] = Json::boolean(boolean.current_value)
      }
    }
    experimental_v2_put_meta(fields, known.meta)
    Json::object(fields)
  })
}

///|
fn experimental_v2_decode_config_options(
  value : Json,
  path~ : String,
) -> Array[ExperimentalV2SessionConfigOption] raise ExperimentalV2DecodeError {
  experimental_v2_decode_array(value, path~, (item, item_path) => {
    experimental_v2_decode_config_option(item, path=item_path)
  })
}

///|
fn experimental_v2_encode_config_options(
  values : Array[ExperimentalV2SessionConfigOption],
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_array(values, experimental_v2_encode_config_option)
}

///|
/// Value of a known `session/set_config_option` payload:
/// `type: "id"` or `type: "boolean"`.
pub(all) enum ExperimentalV2ConfigValue {
  ConfigValueId(String)
  ConfigValueBoolean(Bool)
} derive(Eq, Debug)

///|
/// Known shape of `session/set_config_option` params.
pub(all) struct ExperimentalV2SetConfigOptionKnown {
  session_id : String
  config_id : String
  value : ExperimentalV2ConfigValue
  meta : Json?
} derive(Eq, Debug)

///|
/// Parameters of `session/set_config_option`.  The `type` discriminator sits
/// on the params object itself and the schema has an open fallback, so
/// custom or future value types stay as `Extension`/`Future` raw payloads.
pub type ExperimentalV2SetConfigOptionParams = ExperimentalV2Open[
  ExperimentalV2SetConfigOptionKnown,
]

///|
pub fn experimental_v2_decode_set_config_option(
  value : Json,
  path? : String = "set_config_option",
) -> ExperimentalV2SetConfigOptionParams raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["id", "boolean"],
    (tag, payload) => {
      let fields = experimental_v2_require_object(payload, path~)
      experimental_v2_reject_unknown(
        fields,
        ["type", "sessionId", "configId", "value", "_meta"],
        prefix=path,
      )
      let session_id = experimental_v2_validate_id(
        experimental_v2_decode_string(
          experimental_v2_required(
            fields,
            "sessionId",
            path=path + ".sessionId",
          ),
          path=path + ".sessionId",
        ),
        field_path=path + ".sessionId",
      )
      let config_id = experimental_v2_validate_id(
        experimental_v2_decode_string(
          experimental_v2_required(fields, "configId", path=path + ".configId"),
          path=path + ".configId",
        ),
        field_path=path + ".configId",
      )
      let config_value : ExperimentalV2ConfigValue = match tag {
        "id" =>
          ConfigValueId(
            experimental_v2_validate_id(
              experimental_v2_decode_string(
                experimental_v2_required(fields, "value", path=path + ".value"),
                path=path + ".value",
              ),
              field_path=path + ".value",
            ),
          )
        _ =>
          ConfigValueBoolean(
            experimental_v2_decode_boolean(
              experimental_v2_required(fields, "value", path=path + ".value"),
              path=path + ".value",
            ),
          )
      }
      let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
      { session_id, config_id, value: config_value, meta, }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_set_config_option(
  value : ExperimentalV2SetConfigOptionParams,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    let fields : Map[String, Json] = Map([])
    fields["sessionId"] = Json::string(known.session_id)
    fields["configId"] = Json::string(known.config_id)
    match known.value {
      ConfigValueId(id) => {
        fields["type"] = Json::string("id")
        fields["value"] = Json::string(id)
      }
      ConfigValueBoolean(flag) => {
        fields["type"] = Json::string("boolean")
        fields["value"] = Json::boolean(flag)
      }
    }
    experimental_v2_put_meta(fields, known.meta)
    Json::object(fields)
  })
}

///|
/// Result of `session/set_config_option`: the complete option set.
pub(all) struct ExperimentalV2SetConfigOptionResult {
  config_options : Array[ExperimentalV2SessionConfigOption]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_set_config_option_result(
  value : Json,
  path? : String = "set_config_option",
) -> ExperimentalV2SetConfigOptionResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "configOptions"],
    prefix=path,
  )
  let config_options = experimental_v2_decode_config_options(
    experimental_v2_required(
      fields,
      "configOptions",
      path=path + ".configOptions",
    ),
    path=path + ".configOptions",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { config_options, meta, }
}

///|
pub fn experimental_v2_encode_set_config_option_result(
  value : ExperimentalV2SetConfigOptionResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["configOptions"] = experimental_v2_encode_config_options(
    value.config_options,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
