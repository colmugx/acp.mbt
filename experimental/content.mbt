///|
/// Conversation role with the schema's open fallback: `_`-prefixed roles are
/// implementation extensions and other unknown roles are future values.
pub(all) enum ExperimentalV2Role {
  RoleUser
  RoleAssistant
  RoleExtension(tag~ : String)
  RoleFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_role(
  value : Json,
  path? : String = "role",
) -> ExperimentalV2Role raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "user" => RoleUser
    "assistant" => RoleAssistant
    _ =>
      if tag.has_prefix("_") {
        RoleExtension(tag~)
      } else {
        RoleFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_role(value : ExperimentalV2Role) -> Json {
  match value {
    RoleUser => Json::string("user")
    RoleAssistant => Json::string("assistant")
    RoleExtension(tag~) => Json::string(tag)
    RoleFuture(raw~) => Json::string(raw)
  }
}

///|
/// Optional annotations attached to v2 content blocks.  The schema bounds
/// `priority` to 0..=1; non-finite or out-of-range values are typed failures
/// on both decode and encode.
pub(all) struct ExperimentalV2Annotations {
  audience : Array[ExperimentalV2Role]?
  last_modified : String?
  priority : Double?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_annotations(
  value : Json,
  path? : String = "annotations",
) -> ExperimentalV2Annotations raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "audience", "lastModified", "priority"],
    prefix=path,
  )
  let audience = experimental_v2_decode_optional(
    fields,
    "audience",
    path=path + ".audience",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_role(item, path=item_path)
      })
    },
  )
  let last_modified = experimental_v2_decode_optional(
    fields,
    "lastModified",
    path=path + ".lastModified",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let priority = experimental_v2_decode_optional(
    fields,
    "priority",
    path=path + ".priority",
    (value, path) => experimental_v2_decode_priority(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { audience, last_modified, priority, meta, }
}

///|
pub fn experimental_v2_encode_annotations(
  value : ExperimentalV2Annotations,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "audience", value.audience, values => {
    experimental_v2_encode_array(values, value => {
      experimental_v2_encode_role(value)
    })
  })
  experimental_v2_put_optional(fields, "lastModified", value.last_modified, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "priority", value.priority, value => {
    Json::number(experimental_v2_encode_priority(value))
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn experimental_v2_decode_priority(
  value : Json,
  path~ : String,
) -> Double raise ExperimentalV2DecodeError {
  let number = experimental_v2_decode_finite_number(value, path~)
  if number < 0.0 || number > 1.0 {
    raise InvalidField(path~, reason="priority must be within 0 and 1")
  }
  number
}

///|
fn experimental_v2_encode_priority(
  value : Double,
) -> Double raise ExperimentalV2DecodeError {
  if value.is_nan() || value.is_inf() || value < 0.0 || value > 1.0 {
    raise InvalidField(
      path="priority",
      reason="priority must be within 0 and 1",
    )
  }
  value
}

///|
fn experimental_v2_decode_optional_annotations(
  fields : Map[String, Json],
  path~ : String,
) -> ExperimentalV2Annotations? raise ExperimentalV2DecodeError {
  experimental_v2_decode_optional(
    fields,
    "annotations",
    path=path + ".annotations",
    (value, path) => experimental_v2_decode_annotations(value, path~),
  )
}

///|
fn experimental_v2_put_annotations(
  fields : Map[String, Json],
  value : ExperimentalV2Annotations?,
) -> Unit raise ExperimentalV2DecodeError {
  experimental_v2_put_optional(
    fields, "annotations", value, experimental_v2_encode_annotations,
  )
}

///|
/// Text provided to or from a language model.
pub(all) struct ExperimentalV2TextContent {
  text : String
  annotations : ExperimentalV2Annotations?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_text_content(
  value : Json,
  path? : String = "text",
) -> ExperimentalV2TextContent raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "text", "annotations", "_meta"],
    prefix=path,
  )
  let text = experimental_v2_decode_string(
    experimental_v2_required(fields, "text", path=path + ".text"),
    path=path + ".text",
  )
  let annotations = experimental_v2_decode_optional_annotations(fields, path~)
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { text, annotations, meta, }
}

///|
pub fn experimental_v2_encode_text_content(
  value : ExperimentalV2TextContent,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["text"] = Json::string(value.text)
  experimental_v2_put_annotations(fields, value.annotations)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// An image provided to or from a language model.
pub(all) struct ExperimentalV2ImageContent {
  data : String
  mime_type : String
  uri : String?
  annotations : ExperimentalV2Annotations?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_image_content(
  value : Json,
  path? : String = "image",
) -> ExperimentalV2ImageContent raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "data", "mimeType", "uri", "annotations", "_meta"],
    prefix=path,
  )
  let data = experimental_v2_validate_base64(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "data", path=path + ".data"),
      path=path + ".data",
    ),
    field_path=path + ".data",
  )
  let mime_type = experimental_v2_decode_string(
    experimental_v2_required(fields, "mimeType", path=path + ".mimeType"),
    path=path + ".mimeType",
  )
  let uri = experimental_v2_decode_optional(fields, "uri", path=path + ".uri", (
    value,
    path,
  ) => experimental_v2_decode_string(value, path~))
  let annotations = experimental_v2_decode_optional_annotations(fields, path~)
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { data, mime_type, uri, annotations, meta, }
}

///|
pub fn experimental_v2_encode_image_content(
  value : ExperimentalV2ImageContent,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["data"] = Json::string(
    experimental_v2_validate_base64(value.data, field_path="data"),
  )
  fields["mimeType"] = Json::string(value.mime_type)
  experimental_v2_put_optional(fields, "uri", value.uri, value => {
    Json::string(value)
  })
  experimental_v2_put_annotations(fields, value.annotations)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Audio provided to or from a language model.
pub(all) struct ExperimentalV2AudioContent {
  data : String
  mime_type : String
  annotations : ExperimentalV2Annotations?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_audio_content(
  value : Json,
  path? : String = "audio",
) -> ExperimentalV2AudioContent raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "data", "mimeType", "annotations", "_meta"],
    prefix=path,
  )
  let data = experimental_v2_validate_base64(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "data", path=path + ".data"),
      path=path + ".data",
    ),
    field_path=path + ".data",
  )
  let mime_type = experimental_v2_decode_string(
    experimental_v2_required(fields, "mimeType", path=path + ".mimeType"),
    path=path + ".mimeType",
  )
  let annotations = experimental_v2_decode_optional_annotations(fields, path~)
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { data, mime_type, annotations, meta, }
}

///|
pub fn experimental_v2_encode_audio_content(
  value : ExperimentalV2AudioContent,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["data"] = Json::string(
    experimental_v2_validate_base64(value.data, field_path="data"),
  )
  fields["mimeType"] = Json::string(value.mime_type)
  experimental_v2_put_annotations(fields, value.annotations)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Theme an icon is designed for, with the schema's open fallback.
pub(all) enum ExperimentalV2IconTheme {
  IconThemeLight
  IconThemeDark
  IconThemeExtension(tag~ : String)
  IconThemeFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_icon_theme(
  value : Json,
  path? : String = "theme",
) -> ExperimentalV2IconTheme raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "light" => IconThemeLight
    "dark" => IconThemeDark
    _ =>
      if tag.has_prefix("_") {
        IconThemeExtension(tag~)
      } else {
        IconThemeFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_icon_theme(
  value : ExperimentalV2IconTheme,
) -> Json {
  match value {
    IconThemeLight => Json::string("light")
    IconThemeDark => Json::string("dark")
    IconThemeExtension(tag~) => Json::string(tag)
    IconThemeFuture(raw~) => Json::string(raw)
  }
}

///|
/// One optionally-sized icon a client can display in a user interface.
pub(all) struct ExperimentalV2Icon {
  src : String
  mime_type : String?
  sizes : Array[String]?
  theme : ExperimentalV2IconTheme?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_icon(
  value : Json,
  path? : String = "icon",
) -> ExperimentalV2Icon raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["src", "mimeType", "sizes", "theme"],
    prefix=path,
  )
  let src = experimental_v2_decode_string(
    experimental_v2_required(fields, "src", path=path + ".src"),
    path=path + ".src",
  )
  let mime_type = experimental_v2_decode_optional(
    fields,
    "mimeType",
    path=path + ".mimeType",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let sizes = experimental_v2_decode_optional(
    fields,
    "sizes",
    path=path + ".sizes",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_string(item, path=item_path)
      })
    },
  )
  let theme = experimental_v2_decode_optional(
    fields,
    "theme",
    path=path + ".theme",
    (value, path) => experimental_v2_decode_icon_theme(value, path~),
  )
  { src, mime_type, sizes, theme, }
}

///|
pub fn experimental_v2_encode_icon(
  value : ExperimentalV2Icon,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["src"] = Json::string(value.src)
  experimental_v2_put_optional(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "sizes", value.sizes, values => {
    experimental_v2_encode_array(values, value => Json::string(value))
  })
  experimental_v2_put_optional(fields, "theme", value.theme, value => {
    experimental_v2_encode_icon_theme(value)
  })
  Json::object(fields)
}

///|
/// A resource that the server is capable of reading, included in a prompt or
/// tool call result.
pub(all) struct ExperimentalV2ResourceLink {
  name : String
  uri : String
  title : String?
  description : String?
  icons : Array[ExperimentalV2Icon]?
  mime_type : String?
  size : Int64?
  annotations : ExperimentalV2Annotations?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_resource_link(
  value : Json,
  path? : String = "resource_link",
) -> ExperimentalV2ResourceLink raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    [
      "type", "name", "uri", "title", "description", "icons", "mimeType", "size",
      "annotations", "_meta",
    ],
    prefix=path,
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let uri = experimental_v2_decode_string(
    experimental_v2_required(fields, "uri", path=path + ".uri"),
    path=path + ".uri",
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
  let icons = experimental_v2_decode_optional(
    fields,
    "icons",
    path=path + ".icons",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_icon(item, path=item_path)
      })
    },
  )
  let mime_type = experimental_v2_decode_optional(
    fields,
    "mimeType",
    path=path + ".mimeType",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let size = experimental_v2_decode_optional(
    fields,
    "size",
    path=path + ".size",
    (value, path) => experimental_v2_decode_int64(value, path~),
  )
  let annotations = experimental_v2_decode_optional_annotations(fields, path~)
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { name, uri, title, description, icons, mime_type, size, annotations, meta, }
}

///|
pub fn experimental_v2_encode_resource_link(
  value : ExperimentalV2ResourceLink,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  fields["uri"] = Json::string(value.uri)
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "icons", value.icons, values => {
    experimental_v2_encode_array(values, experimental_v2_encode_icon)
  })
  experimental_v2_put_optional(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "size", value.size, value => {
    experimental_v2_encode_int64(value)
  })
  experimental_v2_put_annotations(fields, value.annotations)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Text-based resource contents embedded directly in a message.
pub(all) struct ExperimentalV2TextResourceContents {
  text : String
  uri : String
  mime_type : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_text_resource_contents(
  value : Json,
  path? : String = "resource",
) -> ExperimentalV2TextResourceContents raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["text", "uri", "mimeType", "_meta"],
    prefix=path,
  )
  let text = experimental_v2_decode_string(
    experimental_v2_required(fields, "text", path=path + ".text"),
    path=path + ".text",
  )
  let uri = experimental_v2_decode_string(
    experimental_v2_required(fields, "uri", path=path + ".uri"),
    path=path + ".uri",
  )
  let mime_type = experimental_v2_decode_optional(
    fields,
    "mimeType",
    path=path + ".mimeType",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { text, uri, mime_type, meta, }
}

///|
pub fn experimental_v2_encode_text_resource_contents(
  value : ExperimentalV2TextResourceContents,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["text"] = Json::string(value.text)
  fields["uri"] = Json::string(value.uri)
  experimental_v2_put_optional(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Binary resource contents embedded directly in a message.
pub(all) struct ExperimentalV2BlobResourceContents {
  blob : String
  uri : String
  mime_type : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_blob_resource_contents(
  value : Json,
  path? : String = "resource",
) -> ExperimentalV2BlobResourceContents raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["blob", "uri", "mimeType", "_meta"],
    prefix=path,
  )
  let blob = experimental_v2_validate_base64(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "blob", path=path + ".blob"),
      path=path + ".blob",
    ),
    field_path=path + ".blob",
  )
  let uri = experimental_v2_decode_string(
    experimental_v2_required(fields, "uri", path=path + ".uri"),
    path=path + ".uri",
  )
  let mime_type = experimental_v2_decode_optional(
    fields,
    "mimeType",
    path=path + ".mimeType",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { blob, uri, mime_type, meta, }
}

///|
pub fn experimental_v2_encode_blob_resource_contents(
  value : ExperimentalV2BlobResourceContents,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["blob"] = Json::string(
    experimental_v2_validate_base64(value.blob, field_path="blob"),
  )
  fields["uri"] = Json::string(value.uri)
  experimental_v2_put_optional(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The two resource payloads accepted by an embedded resource.  The schema
/// discriminated them only by payload field: `text` or `blob`.
pub(all) enum ExperimentalV2EmbeddedResourceResource {
  ResourceText(ExperimentalV2TextResourceContents)
  ResourceBlob(ExperimentalV2BlobResourceContents)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_embedded_resource_resource(
  value : Json,
  path? : String = "resource",
) -> ExperimentalV2EmbeddedResourceResource raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  let has_text = fields.contains("text")
  let has_blob = fields.contains("blob")
  if has_text && has_blob {
    raise InvalidField(
      path~,
      reason="resource payload cannot contain both text and blob",
    )
  }
  if has_text {
    ResourceText(experimental_v2_decode_text_resource_contents(value, path~))
  } else if has_blob {
    ResourceBlob(experimental_v2_decode_blob_resource_contents(value, path~))
  } else {
    raise InvalidField(
      path~,
      reason="resource payload must contain text or blob",
    )
  }
}

///|
pub fn experimental_v2_encode_embedded_resource_resource(
  value : ExperimentalV2EmbeddedResourceResource,
) -> Json raise ExperimentalV2DecodeError {
  match value {
    ResourceText(value) => experimental_v2_encode_text_resource_contents(value)
    ResourceBlob(value) => experimental_v2_encode_blob_resource_contents(value)
  }
}

///|
/// Complete resource contents embedded directly in a message.
pub(all) struct ExperimentalV2EmbeddedResource {
  resource : ExperimentalV2EmbeddedResourceResource
  annotations : ExperimentalV2Annotations?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_embedded_resource(
  value : Json,
  path? : String = "resource",
) -> ExperimentalV2EmbeddedResource raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "resource", "annotations", "_meta"],
    prefix=path,
  )
  let resource = experimental_v2_decode_embedded_resource_resource(
    experimental_v2_required(fields, "resource", path=path + ".resource"),
    path=path + ".resource",
  )
  let annotations = experimental_v2_decode_optional_annotations(fields, path~)
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { resource, annotations, meta, }
}

///|
pub fn experimental_v2_encode_embedded_resource(
  value : ExperimentalV2EmbeddedResource,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["resource"] = experimental_v2_encode_embedded_resource_resource(
    value.resource,
  )
  experimental_v2_put_annotations(fields, value.annotations)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The five known v2 content block payloads.
pub(all) enum ExperimentalV2ContentBlockKnown {
  BlockText(ExperimentalV2TextContent)
  BlockImage(ExperimentalV2ImageContent)
  BlockAudio(ExperimentalV2AudioContent)
  BlockResourceLink(ExperimentalV2ResourceLink)
  BlockResource(ExperimentalV2EmbeddedResource)
} derive(Eq, Debug)

///|
/// A v2 content block.  The schema has an open fallback: `_`-prefixed block
/// types are implementation extensions and other unknown types are future
/// values; both keep their raw object for byte-faithful replay.
pub type ExperimentalV2ContentBlock = ExperimentalV2Open[
  ExperimentalV2ContentBlockKnown,
]

///|
pub fn experimental_v2_decode_content_block(
  value : Json,
  path? : String = "content",
) -> ExperimentalV2ContentBlock raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["text", "image", "audio", "resource_link", "resource"],
    (tag, payload) => {
      match tag {
        "text" => BlockText(experimental_v2_decode_text_content(payload, path~))
        "image" =>
          BlockImage(experimental_v2_decode_image_content(payload, path~))
        "audio" =>
          BlockAudio(experimental_v2_decode_audio_content(payload, path~))
        "resource_link" =>
          BlockResourceLink(
            experimental_v2_decode_resource_link(payload, path~),
          )
        "resource" =>
          BlockResource(
            experimental_v2_decode_embedded_resource(payload, path~),
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
pub fn experimental_v2_encode_content_block(
  value : ExperimentalV2ContentBlock,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    match known {
      BlockText(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_text_content(value),
          tag_key="type",
          tag="text",
        )
      BlockImage(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_image_content(value),
          tag_key="type",
          tag="image",
        )
      BlockAudio(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_audio_content(value),
          tag_key="type",
          tag="audio",
        )
      BlockResourceLink(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_resource_link(value),
          tag_key="type",
          tag="resource_link",
        )
      BlockResource(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_embedded_resource(value),
          tag_key="type",
          tag="resource",
        )
    }
  })
}

///|
/// A standard content wrapper carrying one block plus protocol metadata.
pub(all) struct ExperimentalV2Content {
  content : ExperimentalV2ContentBlock
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_content(
  value : Json,
  path? : String = "content",
) -> ExperimentalV2Content raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "content", "_meta"],
    prefix=path,
  )
  let content = experimental_v2_decode_content_block(
    experimental_v2_required(fields, "content", path=path + ".content"),
    path=path + ".content",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { content, meta, }
}

///|
pub fn experimental_v2_encode_content(
  value : ExperimentalV2Content,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["content"] = experimental_v2_encode_content_block(value.content)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// One streamed item of message content.
pub(all) struct ExperimentalV2ContentChunk {
  message_id : String
  content : ExperimentalV2ContentBlock
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_content_chunk(
  value : Json,
  path? : String = "contentChunk",
) -> ExperimentalV2ContentChunk raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["messageId", "content", "_meta"],
    prefix=path,
  )
  let message_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "messageId", path=path + ".messageId"),
      path=path + ".messageId",
    ),
    field_path=path + ".messageId",
  )
  let content = experimental_v2_decode_content_block(
    experimental_v2_required(fields, "content", path=path + ".content"),
    path=path + ".content",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { message_id, content, meta, }
}

///|
pub fn experimental_v2_encode_content_chunk(
  value : ExperimentalV2ContentChunk,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["messageId"] = Json::string(value.message_id)
  fields["content"] = experimental_v2_encode_content_block(value.content)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
