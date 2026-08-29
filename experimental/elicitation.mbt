///|
/// JSON-RPC request id as constrained by the v2 schema: `null`, a signed
/// 64-bit integer, or a string.
pub(all) enum ExperimentalV2RequestId {
  RequestIdNull
  RequestIdNumber(Int64)
  RequestIdStr(String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_request_id(
  value : Json,
  path? : String = "requestId",
) -> ExperimentalV2RequestId raise ExperimentalV2DecodeError {
  match value {
    Null => RequestIdNull
    String(text) => RequestIdStr(text)
    Number(_, ..) => RequestIdNumber(experimental_v2_decode_int64(value, path~))
    _ =>
      raise InvalidField(
        path~,
        reason="request id must be a string, an integer, or null",
      )
  }
}

///|
pub fn experimental_v2_encode_request_id(
  value : ExperimentalV2RequestId,
) -> Json {
  match value {
    RequestIdNull => Json::null()
    RequestIdNumber(number) => experimental_v2_encode_int64(number)
    RequestIdStr(text) => Json::string(text)
  }
}

///|
/// A titled enum option shared by single-select `oneOf` lists and titled
/// multi-select `anyOf` lists; `value` is the schema's `const` key.
pub(all) struct ExperimentalV2EnumOption {
  value : String
  title : String
  description : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_enum_option(
  value : Json,
  path? : String = "enumOption",
) -> ExperimentalV2EnumOption raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["const", "title", "description", "_meta"],
    prefix=path,
  )
  let const_value = experimental_v2_decode_string(
    experimental_v2_required(fields, "const", path=path + ".const"),
    path=path + ".const",
  )
  let title = experimental_v2_decode_string(
    experimental_v2_required(fields, "title", path=path + ".title"),
    path=path + ".title",
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { value: const_value, title, description, meta, }
}

///|
pub fn experimental_v2_encode_enum_option(
  value : ExperimentalV2EnumOption,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["const"] = Json::string(value.value)
  fields["title"] = Json::string(value.title)
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// String format annotation of a string property; the schema keeps the set
/// open without an extension split, so any unknown format is preserved.
pub(all) enum ExperimentalV2StringFormat {
  FormatEmail
  FormatUri
  FormatDate
  FormatDateTime
  FormatOther(String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_string_format(
  value : Json,
  path? : String = "format",
) -> ExperimentalV2StringFormat raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "email" => FormatEmail
    "uri" => FormatUri
    "date" => FormatDate
    "date-time" => FormatDateTime
    _ => FormatOther(tag)
  }
}

///|
pub fn experimental_v2_encode_string_format(
  value : ExperimentalV2StringFormat,
) -> Json {
  match value {
    FormatEmail => Json::string("email")
    FormatUri => Json::string("uri")
    FormatDate => Json::string("date")
    FormatDateTime => Json::string("date-time")
    FormatOther(raw) => Json::string(raw)
  }
}

///|
/// String (or single-select enum) form field definition.
pub(all) struct ExperimentalV2StringProperty {
  title : String?
  description : String?
  min_length : UInt?
  max_length : UInt?
  pattern : String?
  format : ExperimentalV2StringFormat?
  default : String?
  enum_values : Array[String]?
  one_of : Array[ExperimentalV2EnumOption]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_string_property(
  value : Json,
  path? : String = "property",
) -> ExperimentalV2StringProperty raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    [
      "type", "title", "description", "minLength", "maxLength", "pattern", "format",
      "default", "enum", "oneOf", "_meta",
    ],
    prefix=path,
  )
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let min_length = experimental_v2_decode_optional(
    fields,
    "minLength",
    path=path + ".minLength",
    (value, path) => experimental_v2_decode_uint32(value, path~),
  )
  let max_length = experimental_v2_decode_optional(
    fields,
    "maxLength",
    path=path + ".maxLength",
    (value, path) => experimental_v2_decode_uint32(value, path~),
  )
  let pattern = experimental_v2_decode_optional(
    fields,
    "pattern",
    path=path + ".pattern",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let format = experimental_v2_decode_optional(
    fields,
    "format",
    path=path + ".format",
    (value, path) => experimental_v2_decode_string_format(value, path~),
  )
  let default = experimental_v2_decode_optional(
    fields,
    "default",
    path=path + ".default",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let enum_values = experimental_v2_decode_optional(
    fields,
    "enum",
    path=path + ".enum",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_string(item, path=item_path)
      })
    },
  )
  experimental_v2_check_min_items(enum_values, field_path=path + ".enum")
  let one_of = experimental_v2_decode_optional(
    fields,
    "oneOf",
    path=path + ".oneOf",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_enum_option(item, path=item_path)
      })
    },
  )
  experimental_v2_check_min_items(one_of, field_path=path + ".oneOf")
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  {
    title,
    description,
    min_length,
    max_length,
    pattern,
    format,
    default,
    enum_values,
    one_of,
    meta,
  }
}

///|
pub fn experimental_v2_encode_string_property(
  value : ExperimentalV2StringProperty,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "minLength", value.min_length, value => {
    Json::number(value.to_double())
  })
  experimental_v2_put_optional(fields, "maxLength", value.max_length, value => {
    Json::number(value.to_double())
  })
  experimental_v2_put_optional(fields, "pattern", value.pattern, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "format", value.format, value => {
    experimental_v2_encode_string_format(value)
  })
  experimental_v2_put_optional(fields, "default", value.default, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "enum", value.enum_values, values => {
    experimental_v2_check_min_items(Some(values), field_path="enum")
    experimental_v2_encode_array(values, value => Json::string(value))
  })
  experimental_v2_put_optional(fields, "oneOf", value.one_of, values => {
    experimental_v2_check_min_items(Some(values), field_path="oneOf")
    experimental_v2_encode_array(values, experimental_v2_encode_enum_option)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Number (floating-point) form field definition.
pub(all) struct ExperimentalV2NumberProperty {
  title : String?
  description : String?
  minimum : Double?
  maximum : Double?
  default : Double?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_number_property(
  value : Json,
  path? : String = "property",
) -> ExperimentalV2NumberProperty raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "title", "description", "minimum", "maximum", "default", "_meta"],
    prefix=path,
  )
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let minimum = experimental_v2_decode_optional(
    fields,
    "minimum",
    path=path + ".minimum",
    (value, path) => experimental_v2_decode_finite_number(value, path~),
  )
  let maximum = experimental_v2_decode_optional(
    fields,
    "maximum",
    path=path + ".maximum",
    (value, path) => experimental_v2_decode_finite_number(value, path~),
  )
  let default = experimental_v2_decode_optional(
    fields,
    "default",
    path=path + ".default",
    (value, path) => experimental_v2_decode_finite_number(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { title, description, minimum, maximum, default, meta, }
}

///|
pub fn experimental_v2_encode_number_property(
  value : ExperimentalV2NumberProperty,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "minimum", value.minimum, minimum => {
    experimental_v2_encode_finite_number(minimum, field_path="minimum")
  })
  experimental_v2_put_optional(fields, "maximum", value.maximum, maximum => {
    experimental_v2_encode_finite_number(maximum, field_path="maximum")
  })
  experimental_v2_put_optional(fields, "default", value.default, default => {
    experimental_v2_encode_finite_number(default, field_path="default")
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Integer form field definition; bounds and defaults are exact int64s.
pub(all) struct ExperimentalV2IntegerProperty {
  title : String?
  description : String?
  minimum : Int64?
  maximum : Int64?
  default : Int64?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_integer_property(
  value : Json,
  path? : String = "property",
) -> ExperimentalV2IntegerProperty raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "title", "description", "minimum", "maximum", "default", "_meta"],
    prefix=path,
  )
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let minimum = experimental_v2_decode_optional(
    fields,
    "minimum",
    path=path + ".minimum",
    (value, path) => experimental_v2_decode_int64(value, path~),
  )
  let maximum = experimental_v2_decode_optional(
    fields,
    "maximum",
    path=path + ".maximum",
    (value, path) => experimental_v2_decode_int64(value, path~),
  )
  let default = experimental_v2_decode_optional(
    fields,
    "default",
    path=path + ".default",
    (value, path) => experimental_v2_decode_int64(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { title, description, minimum, maximum, default, meta, }
}

///|
pub fn experimental_v2_encode_integer_property(
  value : ExperimentalV2IntegerProperty,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "minimum", value.minimum, value => {
    experimental_v2_encode_int64(value)
  })
  experimental_v2_put_optional(fields, "maximum", value.maximum, value => {
    experimental_v2_encode_int64(value)
  })
  experimental_v2_put_optional(fields, "default", value.default, value => {
    experimental_v2_encode_int64(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Boolean form field definition.
pub(all) struct ExperimentalV2BooleanProperty {
  title : String?
  description : String?
  default : Bool?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_boolean_property(
  value : Json,
  path? : String = "property",
) -> ExperimentalV2BooleanProperty raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "title", "description", "default", "_meta"],
    prefix=path,
  )
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let default = experimental_v2_decode_optional(
    fields,
    "default",
    path=path + ".default",
    (value, path) => experimental_v2_decode_boolean(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { title, description, default, meta, }
}

///|
pub fn experimental_v2_encode_boolean_property(
  value : ExperimentalV2BooleanProperty,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "default", value.default, value => {
    Json::boolean(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Multi-select (array) form field definition; `items` names the allowed
/// selections and is required.
pub(all) struct ExperimentalV2MultiSelectProperty {
  title : String?
  description : String?
  min_items : UInt64?
  max_items : UInt64?
  items : ExperimentalV2MultiSelectItems
  default : Array[String]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_multi_select_property(
  value : Json,
  path? : String = "property",
) -> ExperimentalV2MultiSelectProperty raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    [
      "type", "title", "description", "minItems", "maxItems", "items", "default",
      "_meta",
    ],
    prefix=path,
  )
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let min_items = experimental_v2_decode_optional(
    fields,
    "minItems",
    path=path + ".minItems",
    (value, path) => experimental_v2_decode_uint64(value, path~),
  )
  let max_items = experimental_v2_decode_optional(
    fields,
    "maxItems",
    path=path + ".maxItems",
    (value, path) => experimental_v2_decode_uint64(value, path~),
  )
  let items = experimental_v2_decode_multi_select_items(
    experimental_v2_required(fields, "items", path=path + ".items"),
    path=path + ".items",
  )
  let default = experimental_v2_decode_optional(
    fields,
    "default",
    path=path + ".default",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_string(item, path=item_path)
      })
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { title, description, min_items, max_items, items, default, meta, }
}

///|
pub fn experimental_v2_encode_multi_select_property(
  value : ExperimentalV2MultiSelectProperty,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "minItems", value.min_items, value => {
    experimental_v2_encode_uint64(value)
  })
  experimental_v2_put_optional(fields, "maxItems", value.max_items, value => {
    experimental_v2_encode_uint64(value)
  })
  fields["items"] = experimental_v2_encode_multi_select_items(value.items)
  experimental_v2_put_optional(fields, "default", value.default, values => {
    experimental_v2_encode_array(values, value => Json::string(value))
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Untitled multi-select items: a non-empty list of allowed plain strings.
pub(all) struct ExperimentalV2StringMultiSelectItems {
  enum_values : Array[String]
  meta : Json?
} derive(Eq, Debug)

///|
/// Titled multi-select items: a non-empty list of titled options, carried
/// under the `anyOf` key with no `type` discriminator.
pub(all) struct ExperimentalV2TitledMultiSelectItems {
  any_of : Array[ExperimentalV2EnumOption]
  meta : Json?
} derive(Eq, Debug)

///|
/// Items of a multi-select property.  Typed `string` items and titled
/// `anyOf` items are decoded; any other typed items stay as raw payloads,
/// with `_`-prefixed types as extensions and other unknown types as future
/// values.
pub(all) enum ExperimentalV2MultiSelectItems {
  MultiSelectItemsString(ExperimentalV2StringMultiSelectItems)
  MultiSelectItemsTitled(ExperimentalV2TitledMultiSelectItems)
  MultiSelectItemsExtension(tag~ : String, raw~ : Json)
  MultiSelectItemsFuture(tag~ : String, raw~ : Json)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_multi_select_items(
  value : Json,
  path? : String = "items",
) -> ExperimentalV2MultiSelectItems raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  match fields.get("type") {
    Some(String(tag)) =>
      if tag == "string" {
        experimental_v2_reject_unknown(
          fields,
          ["type", "enum", "_meta"],
          prefix=path,
        )
        let enum_values = experimental_v2_decode_array(
          experimental_v2_required(fields, "enum", path=path + ".enum"),
          path=path + ".enum",
          (item, item_path) => {
            experimental_v2_decode_string(item, path=item_path)
          },
        )
        experimental_v2_check_min_items(
          Some(enum_values),
          field_path=path + ".enum",
        )
        let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
        MultiSelectItemsString({ enum_values, meta, })
      } else if tag.has_prefix("_") {
        MultiSelectItemsExtension(tag~, raw=value)
      } else {
        MultiSelectItemsFuture(tag~, raw=value)
      }
    Some(_) => raise ExpectedString(path=path + ".type")
    None =>
      if fields.contains("anyOf") {
        experimental_v2_reject_unknown(fields, ["anyOf", "_meta"], prefix=path)
        let any_of = experimental_v2_decode_array(
          experimental_v2_required(fields, "anyOf", path=path + ".anyOf"),
          path=path + ".anyOf",
          (item, item_path) => {
            experimental_v2_decode_enum_option(item, path=item_path)
          },
        )
        experimental_v2_check_min_items(
          Some(any_of),
          field_path=path + ".anyOf",
        )
        let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
        MultiSelectItemsTitled({ any_of, meta, })
      } else {
        raise InvalidField(
          path~,
          reason="multi-select items must carry a typed enum list or a titled anyOf list",
        )
      }
  }
}

///|
pub fn experimental_v2_encode_multi_select_items(
  value : ExperimentalV2MultiSelectItems,
) -> Json raise ExperimentalV2DecodeError {
  match value {
    MultiSelectItemsString(items) => {
      let fields : Map[String, Json] = Map([])
      fields["type"] = Json::string("string")
      experimental_v2_check_min_items(
        Some(items.enum_values),
        field_path="enum",
      )
      fields["enum"] = experimental_v2_encode_array(items.enum_values, value => {
        Json::string(value)
      })
      experimental_v2_put_meta(fields, items.meta)
      Json::object(fields)
    }
    MultiSelectItemsTitled(items) => {
      let fields : Map[String, Json] = Map([])
      experimental_v2_check_min_items(Some(items.any_of), field_path="anyOf")
      fields["anyOf"] = experimental_v2_encode_array(
        items.any_of,
        experimental_v2_encode_enum_option,
      )
      experimental_v2_put_meta(fields, items.meta)
      Json::object(fields)
    }
    MultiSelectItemsExtension(tag~, raw~)
    | MultiSelectItemsFuture(tag~, raw~) =>
      experimental_v2_verify_raw_tag(raw, tag_key="type", tag~)
  }
}

///|
/// Known elicitation form field definitions; the `type` discriminator is an
/// open union so unknown field kinds stay as raw payloads.
pub(all) enum ExperimentalV2ElicitationPropertyKnown {
  PropertyString(ExperimentalV2StringProperty)
  PropertyNumber(ExperimentalV2NumberProperty)
  PropertyInteger(ExperimentalV2IntegerProperty)
  PropertyBoolean(ExperimentalV2BooleanProperty)
  PropertyMultiSelect(ExperimentalV2MultiSelectProperty)
} derive(Eq, Debug)

///|
/// One elicitation form field definition.
pub type ExperimentalV2ElicitationProperty = ExperimentalV2Open[
  ExperimentalV2ElicitationPropertyKnown,
]

///|
pub fn experimental_v2_decode_elicitation_property(
  value : Json,
  path? : String = "property",
) -> ExperimentalV2ElicitationProperty raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["string", "number", "integer", "boolean", "array"],
    (tag, payload) => {
      match tag {
        "string" =>
          PropertyString(experimental_v2_decode_string_property(payload, path~))
        "number" =>
          PropertyNumber(experimental_v2_decode_number_property(payload, path~))
        "integer" =>
          PropertyInteger(
            experimental_v2_decode_integer_property(payload, path~),
          )
        "boolean" =>
          PropertyBoolean(
            experimental_v2_decode_boolean_property(payload, path~),
          )
        "array" =>
          PropertyMultiSelect(
            experimental_v2_decode_multi_select_property(payload, path~),
          )
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".type", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_elicitation_property(
  value : ExperimentalV2ElicitationProperty,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    match known {
      PropertyString(property) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_string_property(property),
          tag_key="type",
          tag="string",
        )
      PropertyNumber(property) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_number_property(property),
          tag_key="type",
          tag="number",
        )
      PropertyInteger(property) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_integer_property(property),
          tag_key="type",
          tag="integer",
        )
      PropertyBoolean(property) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_boolean_property(property),
          tag_key="type",
          tag="boolean",
        )
      PropertyMultiSelect(property) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_multi_select_property(property),
          tag_key="type",
          tag="array",
        )
    }
  })
}

///|
/// The object schema of a form elicitation: property definitions keyed by
/// name plus the list of required property names.  The wire `type` is the
/// constant `"object"` and is always re-encoded explicitly.
pub(all) struct ExperimentalV2ElicitationSchema {
  title : String?
  properties : Map[String, ExperimentalV2ElicitationProperty]
  required : Array[String]?
  description : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_elicitation_schema(
  value : Json,
  path? : String = "requestedSchema",
) -> ExperimentalV2ElicitationSchema raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "title", "properties", "required", "description", "_meta"],
    prefix=path,
  )
  match fields.get("type") {
    Some(String("object")) => ()
    Some(_) =>
      raise InvalidField(
        path=path + ".type",
        reason="elicitation schema type must be \"object\"",
      )
    None => ()
  }
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let properties : Map[String, ExperimentalV2ElicitationProperty] = Map([])
  match fields.get("properties") {
    Some(Object(definitions)) =>
      for key, definition in definitions {
        properties[key] = experimental_v2_decode_elicitation_property(
          definition,
          path=path + ".properties." + key,
        )
      }
    Some(_) => raise ExpectedObject(path=path + ".properties")
    None => ()
  }
  let required = experimental_v2_decode_optional(
    fields,
    "required",
    path=path + ".required",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_string(item, path=item_path)
      })
    },
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { title, properties, required, description, meta, }
}

///|
pub fn experimental_v2_encode_elicitation_schema(
  value : ExperimentalV2ElicitationSchema,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string("object")
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  let properties : Map[String, Json] = Map([])
  for key, property in value.properties {
    properties[key] = experimental_v2_encode_elicitation_property(property)
  }
  fields["properties"] = Json::object(properties)
  experimental_v2_put_optional(fields, "required", value.required, values => {
    experimental_v2_encode_array(values, value => Json::string(value))
  })
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Session scope: the elicitation is tied to a session, optionally to one
/// tool call inside it.
pub(all) struct ExperimentalV2ElicitationSessionScope {
  session_id : String
  tool_call_id : String?
} derive(Eq, Debug)

///|
/// Request scope: the elicitation is tied to one JSON-RPC request outside
/// any session.
pub(all) struct ExperimentalV2ElicitationRequestScope {
  request_id : ExperimentalV2RequestId
} derive(Eq, Debug)

///|
/// The scope an elicitation is tied to; discriminated by which scope key the
/// payload carries, so carrying both is a typed failure.
pub(all) enum ExperimentalV2ElicitationScope {
  ScopeSession(ExperimentalV2ElicitationSessionScope)
  ScopeRequest(ExperimentalV2ElicitationRequestScope)
} derive(Eq, Debug)

///|
/// Read one scope from the flattened fields of an elicitation request.
fn experimental_v2_decode_elicitation_scope(
  fields : Map[String, Json],
  path~ : String,
) -> ExperimentalV2ElicitationScope raise ExperimentalV2DecodeError {
  let has_session = fields.contains("sessionId")
  let has_request = fields.contains("requestId")
  if has_session && has_request {
    raise InvalidField(
      path~,
      reason="elicitation scope must carry either sessionId or requestId, not both",
    )
  }
  if has_session {
    let session_id = experimental_v2_validate_id(
      experimental_v2_decode_string(
        experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
        path=path + ".sessionId",
      ),
      field_path=path + ".sessionId",
    )
    let tool_call_id = experimental_v2_decode_optional(
      fields,
      "toolCallId",
      path=path + ".toolCallId",
      (value, path) => {
        experimental_v2_validate_id(
          experimental_v2_decode_string(value, path~),
          field_path=path,
        )
      },
    )
    ScopeSession({ session_id, tool_call_id, })
  } else if has_request {
    let request_id = experimental_v2_decode_request_id(
      experimental_v2_required(fields, "requestId", path=path + ".requestId"),
      path=path + ".requestId",
    )
    ScopeRequest({ request_id, })
  } else {
    raise InvalidField(
      path~,
      reason="elicitation scope must carry sessionId or requestId",
    )
  }
}

///|
/// Write one scope back into the flattened fields of an elicitation request.
fn experimental_v2_put_elicitation_scope(
  fields : Map[String, Json],
  scope : ExperimentalV2ElicitationScope,
) -> Unit raise ExperimentalV2DecodeError {
  match scope {
    ScopeSession(session) => {
      fields["sessionId"] = Json::string(session.session_id)
      experimental_v2_put_optional(fields, "toolCallId", session.tool_call_id, value => {
        Json::string(value)
      })
    }
    ScopeRequest(request) =>
      fields["requestId"] = experimental_v2_encode_request_id(
        request.request_id,
      )
  }
}

///|
/// Form mode: the client renders a form described by `requested_schema`.
pub(all) struct ExperimentalV2ElicitationFormMode {
  requested_schema : ExperimentalV2ElicitationSchema
  scope : ExperimentalV2ElicitationScope
} derive(Eq, Debug)

///|
/// URL mode: the client directs the user to `url` and later receives the
/// matching `elicitation/complete` notification.
pub(all) struct ExperimentalV2ElicitationUrlMode {
  elicitation_id : String
  url : String
  scope : ExperimentalV2ElicitationScope
} derive(Eq, Debug)

///|
/// The known `mode` payloads of an `elicitation/create` request.
pub(all) enum ExperimentalV2ElicitationKnownMode {
  ElicitationForm(ExperimentalV2ElicitationFormMode)
  ElicitationUrl(ExperimentalV2ElicitationUrlMode)
} derive(Eq, Debug)

///|
/// Parameters of `elicitation/create`: one human-readable `message` plus a
/// `mode`-discriminated payload.  The discriminator is an open union, so
/// custom or future modes keep their whole raw request object for
/// byte-faithful replay.
pub(all) struct ExperimentalV2ElicitationCreateRequestKnown {
  message : String
  mode : ExperimentalV2ElicitationKnownMode
  meta : Json?
} derive(Eq, Debug)

///|
pub type ExperimentalV2ElicitationCreateRequest = ExperimentalV2Open[
  ExperimentalV2ElicitationCreateRequestKnown,
]

///|
pub fn experimental_v2_decode_elicitation_create_request(
  value : Json,
  path? : String = "elicitation/create",
) -> ExperimentalV2ElicitationCreateRequest raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="mode",
    ["form", "url"],
    (tag, payload) => {
      let fields = experimental_v2_require_object(payload, path~)
      match tag {
        "form" => {
          experimental_v2_reject_unknown(
            fields,
            [
              "mode", "message", "_meta", "requestedSchema", "sessionId", "requestId",
              "toolCallId",
            ],
            prefix=path,
          )
          let message = experimental_v2_decode_string(
            experimental_v2_required(fields, "message", path=path + ".message"),
            path=path + ".message",
          )
          let scope = experimental_v2_decode_elicitation_scope(fields, path~)
          let requested_schema = experimental_v2_decode_elicitation_schema(
            experimental_v2_required(
              fields,
              "requestedSchema",
              path=path + ".requestedSchema",
            ),
            path=path + ".requestedSchema",
          )
          let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
          {
            message,
            mode: ElicitationForm({ requested_schema, scope, }),
            meta,
          }
        }
        "url" => {
          experimental_v2_reject_unknown(
            fields,
            [
              "mode", "message", "_meta", "elicitationId", "url", "sessionId", "requestId",
              "toolCallId",
            ],
            prefix=path,
          )
          let message = experimental_v2_decode_string(
            experimental_v2_required(fields, "message", path=path + ".message"),
            path=path + ".message",
          )
          let scope = experimental_v2_decode_elicitation_scope(fields, path~)
          let elicitation_id = experimental_v2_validate_id(
            experimental_v2_decode_string(
              experimental_v2_required(
                fields,
                "elicitationId",
                path=path + ".elicitationId",
              ),
              path=path + ".elicitationId",
            ),
            field_path=path + ".elicitationId",
          )
          let url = experimental_v2_decode_string(
            experimental_v2_required(fields, "url", path=path + ".url"),
            path=path + ".url",
          )
          let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
          {
            message,
            mode: ElicitationUrl({ elicitation_id, url, scope, }),
            meta,
          }
        }
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".mode", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_elicitation_create_request(
  value : ExperimentalV2ElicitationCreateRequest,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="mode", known => {
    let fields : Map[String, Json] = Map([])
    fields["message"] = Json::string(known.message)
    match known.mode {
      ElicitationForm(form) => {
        experimental_v2_put_elicitation_scope(fields, form.scope)
        fields["requestedSchema"] = experimental_v2_encode_elicitation_schema(
          form.requested_schema,
        )
        experimental_v2_put_meta(fields, known.meta)
        experimental_v2_tag_payload(
          Json::object(fields),
          tag_key="mode",
          tag="form",
        )
      }
      ElicitationUrl(url_mode) => {
        experimental_v2_put_elicitation_scope(fields, url_mode.scope)
        fields["elicitationId"] = Json::string(url_mode.elicitation_id)
        fields["url"] = Json::string(url_mode.url)
        experimental_v2_put_meta(fields, known.meta)
        experimental_v2_tag_payload(
          Json::object(fields),
          tag_key="mode",
          tag="url",
        )
      }
    }
  })
}

///|
/// One accepted value of an elicitation response `content` object.
pub(all) enum ExperimentalV2ElicitationContentValue {
  ContentString(String)
  ContentInteger(Int64)
  ContentNumber(Double)
  ContentBoolean(Bool)
  ContentStringArray(Array[String])
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_elicitation_content_value(
  value : Json,
  path? : String = "content",
) -> ExperimentalV2ElicitationContentValue raise ExperimentalV2DecodeError {
  match value {
    String(text) => ContentString(text)
    True => ContentBoolean(true)
    False => ContentBoolean(false)
    Number(number, repr~) =>
      match repr {
        Some(text) =>
          if experimental_v2_repr_is_integer(text) {
            ContentInteger(experimental_v2_parse_int64_repr(text, path~))
          } else {
            ContentNumber(experimental_v2_decode_finite_number(value, path~))
          }
        None =>
          if number == number.floor() &&
            number.abs() <= 9007199254740991.0 &&
            number >= -9007199254740991.0 {
            ContentInteger(number.to_int64())
          } else {
            ContentNumber(experimental_v2_decode_finite_number(value, path~))
          }
      }
    Array(items) => {
      let values : Array[String] = []
      for index in 0..<items.length() {
        values.push(
          experimental_v2_decode_string(items[index], path=path + ".\{index}"),
        )
      }
      ContentStringArray(values)
    }
    Null | Object(_) =>
      raise InvalidField(
        path~,
        reason="elicitation content values must be strings, numbers, booleans, or string arrays",
      )
  }
}

///|
pub fn experimental_v2_encode_elicitation_content_value(
  value : ExperimentalV2ElicitationContentValue,
) -> Json raise ExperimentalV2DecodeError {
  match value {
    ContentString(text) => Json::string(text)
    ContentInteger(number) => experimental_v2_encode_int64(number)
    ContentNumber(number) =>
      if number.is_nan() || number.is_inf() {
        raise InvalidField(path="content", reason="number must be finite")
      } else {
        Json::number(number)
      }
    ContentBoolean(flag) => Json::boolean(flag)
    ContentStringArray(values) =>
      experimental_v2_encode_array(values, value => Json::string(value))
  }
}

///|
/// `action: "accept"` payload: the user-provided content object, when any.
pub(all) struct ExperimentalV2ElicitationAcceptAction {
  content : Map[String, ExperimentalV2ElicitationContentValue]?
} derive(Eq, Debug)

///|
/// The known `action` payloads of an `elicitation/create` result.  Decline
/// and cancel carry no fields of their own.
pub(all) enum ExperimentalV2ElicitationAction {
  ActionAccept(ExperimentalV2ElicitationAcceptAction)
  ActionDecline
  ActionCancel
} derive(Eq, Debug)

///|
/// Result of `elicitation/create`: an `action`-discriminated payload.  The
/// discriminator is an open union, so custom or future actions keep their
/// whole raw result object for byte-faithful replay.
pub(all) struct ExperimentalV2ElicitationCreateResponseKnown {
  action : ExperimentalV2ElicitationAction
  meta : Json?
} derive(Eq, Debug)

///|
pub type ExperimentalV2ElicitationCreateResponse = ExperimentalV2Open[
  ExperimentalV2ElicitationCreateResponseKnown,
]

///|
pub fn experimental_v2_decode_elicitation_create_response(
  value : Json,
  path? : String = "elicitation/create",
) -> ExperimentalV2ElicitationCreateResponse raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="action",
    ["accept", "decline", "cancel"],
    (tag, payload) => {
      let fields = experimental_v2_require_object(payload, path~)
      match tag {
        "accept" => {
          experimental_v2_reject_unknown(
            fields,
            ["action", "content", "_meta"],
            prefix=path,
          )
          let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
          let content = experimental_v2_decode_optional(
            fields,
            "content",
            path=path + ".content",
            (value, path) => {
              let entries = experimental_v2_require_object(value, path~)
              let decoded : Map[String, ExperimentalV2ElicitationContentValue] = Map([],
              )
              for key, entry in entries {
                decoded[key] = experimental_v2_decode_elicitation_content_value(
                  entry,
                  path=path + "." + key,
                )
              }
              decoded
            },
          )
          { action: ActionAccept({ content, }), meta, }
        }
        "decline" => {
          experimental_v2_reject_unknown(
            fields,
            ["action", "_meta"],
            prefix=path,
          )
          let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
          { action: ActionDecline, meta, }
        }
        "cancel" => {
          experimental_v2_reject_unknown(
            fields,
            ["action", "_meta"],
            prefix=path,
          )
          let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
          { action: ActionCancel, meta, }
        }
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".action", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_elicitation_create_response(
  value : ExperimentalV2ElicitationCreateResponse,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="action", known => {
    let fields : Map[String, Json] = Map([])
    match known.action {
      ActionAccept(accept) => {
        match accept.content {
          Some(content) => {
            let encoded : Map[String, Json] = Map([])
            for key, entry in content {
              encoded[key] = experimental_v2_encode_elicitation_content_value(
                entry,
              )
            }
            fields["content"] = Json::object(encoded)
          }
          None => ()
        }
        experimental_v2_put_meta(fields, known.meta)
        experimental_v2_tag_payload(
          Json::object(fields),
          tag_key="action",
          tag="accept",
        )
      }
      ActionDecline => {
        experimental_v2_put_meta(fields, known.meta)
        experimental_v2_tag_payload(
          Json::object(fields),
          tag_key="action",
          tag="decline",
        )
      }
      ActionCancel => {
        experimental_v2_put_meta(fields, known.meta)
        experimental_v2_tag_payload(
          Json::object(fields),
          tag_key="action",
          tag="cancel",
        )
      }
    }
  })
}

///|
/// Parameters of the `elicitation/complete` notification: the URL-mode
/// elicitation that finished.
pub(all) struct ExperimentalV2CompleteElicitationNotification {
  elicitation_id : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_complete_elicitation_notification(
  value : Json,
  path? : String = "elicitation/complete",
) -> ExperimentalV2CompleteElicitationNotification raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["elicitationId", "_meta"],
    prefix=path,
  )
  let elicitation_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(
        fields,
        "elicitationId",
        path=path + ".elicitationId",
      ),
      path=path + ".elicitationId",
    ),
    field_path=path + ".elicitationId",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { elicitation_id, meta, }
}

///|
pub fn experimental_v2_encode_complete_elicitation_notification(
  value : ExperimentalV2CompleteElicitationNotification,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["elicitationId"] = Json::string(value.elicitation_id)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Reject an option list that is present but empty; `minItems: 1` applies on
/// both decode and encode.
fn[T] experimental_v2_check_min_items(
  values : Array[T]?,
  field_path~ : String,
) -> Unit raise ExperimentalV2DecodeError {
  match values {
    Some(values) =>
      if values.length() == 0 {
        raise InvalidField(
          path=field_path,
          reason="option lists must contain at least one entry",
        )
      }
    None => ()
  }
}

///|
/// A decimal integer run (optionally negative) with no fraction or exponent.
fn experimental_v2_repr_is_integer(text : String) -> Bool {
  let chars = text.to_array()
  let length = chars.length()
  let start = if length > 0 && chars[0] == '-' { 1 } else { 0 }
  if start >= length {
    return false
  }
  let mut integer = true
  for index in start..<length {
    if chars[index] < '0' || chars[index] > '9' {
      integer = false
      break
    }
  }
  integer
}

///|
fn experimental_v2_encode_finite_number(
  value : Double,
  field_path~ : String,
) -> Json raise ExperimentalV2DecodeError {
  if value.is_nan() || value.is_inf() {
    raise InvalidField(path=field_path, reason="number must be finite")
  } else {
    Json::number(value)
  }
}

///|
/// Re-emit an extension/future raw object after checking it still carries
/// its variant tag.
fn experimental_v2_verify_raw_tag(
  raw : Json,
  tag_key~ : String,
  tag~ : String,
) -> Json raise ExperimentalV2DecodeError {
  match raw {
    Object(fields) =>
      match fields.get(tag_key) {
        Some(String(actual)) =>
          if actual == tag {
            raw
          } else {
            raise InvalidField(
              path=tag_key,
              reason="open-union raw payload tag does not match its variant",
            )
          }
        _ =>
          raise InvalidField(
            path=tag_key,
            reason="open-union raw payload must carry its tag in \"" +
              tag_key +
              "\"",
          )
      }
    _ =>
      raise InvalidField(
        path=tag_key,
        reason="open-union raw payload must carry its tag in \"" +
          tag_key +
          "\"",
      )
  }
}
