///|
/// Optional annotations attached to content blocks.
pub(all) struct Annotations {
  audience : ProtocolNullable[Array[Role]]
  last_modified : ProtocolNullable[String]
  priority : ProtocolNullable[Double]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Text provided to or from an LLM.
pub(all) struct TextContent {
  annotations : ProtocolNullable[Annotations]
  text : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// An image provided to or from an LLM.
pub(all) struct ImageContent {
  annotations : ProtocolNullable[Annotations]
  data : String
  mime_type : String
  uri : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Audio provided to or from an LLM.
pub(all) struct AudioContent {
  annotations : ProtocolNullable[Annotations]
  data : String
  mime_type : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// A resource that the server can read.
pub(all) struct ResourceLink {
  annotations : ProtocolNullable[Annotations]
  description : ProtocolNullable[String]
  mime_type : ProtocolNullable[String]
  name : String
  size : ProtocolNullable[Int64]
  title : ProtocolNullable[String]
  uri : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Text-based resource contents embedded directly in a message.
pub(all) struct TextResourceContents {
  mime_type : ProtocolNullable[String]
  text : String
  uri : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Binary resource contents embedded directly in a message.
pub(all) struct BlobResourceContents {
  blob : String
  mime_type : ProtocolNullable[String]
  uri : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// The two resource payloads accepted by an embedded resource.
pub(all) enum EmbeddedResourceResource {
  Text(TextResourceContents)
  Blob(BlobResourceContents)
} derive(Eq, Debug)

///|
/// Complete resource contents embedded directly in a message.
pub(all) struct EmbeddedResource {
  annotations : ProtocolNullable[Annotations]
  resource : EmbeddedResourceResource
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// The five stable ACP content block variants.
pub(all) enum ContentBlock {
  Text(TextContent)
  Image(ImageContent)
  Audio(AudioContent)
  ResourceLink(ResourceLink)
  Resource(EmbeddedResource)
} derive(Eq, Debug)

///|
/// A standard content wrapper.
pub(all) struct Content {
  content : ContentBlock
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// One streamed content item.
pub(all) struct ContentChunk {
  content : ContentBlock
  message_id : ProtocolNullable[MessageId]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn decode_role_array(
  value : Json,
  path~ : String,
) -> Array[Role] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let roles : Array[Role] = []
  for index, value in values {
    roles.push(
      protocol_decode_role(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  roles
}

///|
fn encode_role_array(values : Array[Role]) -> Json {
  Json::array(values.map(value => protocol_encode_role(value)))
}

///|
fn decode_nullable_annotations(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[Annotations] raise ProtocolDecodeError {
  match protocol_field(fields, "annotations") {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(annotations_from_json(value, path=path + ".annotations"))
  }
}

///|
fn put_nullable_annotations(
  fields : Map[String, Json],
  value : ProtocolNullable[Annotations],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields["annotations"] = Json::null()
    Value(value) => fields["annotations"] = annotations_to_json(value)
  }
}

///|
fn decode_finite_number(
  value : Json,
  path~ : String,
) -> Double raise ProtocolDecodeError {
  let number = protocol_decode_number(value, path~)
  if number.is_nan() || number.is_inf() {
    raise InvalidField(path~, reason="number must be finite")
  }
  number
}

///|
fn encode_finite_number(
  value : Double,
  path~ : String,
) -> Json raise ProtocolDecodeError {
  if value.is_nan() || value.is_inf() {
    raise InvalidField(path~, reason="number must be finite")
  }
  Json::number(value)
}

///|
fn decode_annotations_fields(
  fields : Map[String, Json],
  path~ : String,
) -> Annotations raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["audience", "lastModified", "priority", "_meta"],
    prefix=path,
  )
  let audience : ProtocolNullable[Array[Role]] = match
    protocol_field(fields, "audience") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(decode_role_array(value, path=path + ".audience"))
  }
  let last_modified = protocol_nullable_string(
    fields,
    "lastModified",
    path=path + ".lastModified",
  )
  let priority : ProtocolNullable[Double] = match
    protocol_field(fields, "priority") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(decode_finite_number(value, path=path + ".priority"))
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { audience, last_modified, priority, meta, }
}

///|
/// Decode annotations from a JSON value.
pub fn annotations_from_json(
  value : Json,
  path? : String = "annotations",
) -> Annotations raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_annotations_fields(fields, path~)
}

///|
/// Encode annotations as a JSON object.
pub fn annotations_to_json(
  value : Annotations,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  match value.audience {
    Omitted => ()
    Null => fields["audience"] = Json::null()
    Value(audience) => fields["audience"] = encode_role_array(audience)
  }
  match value.last_modified {
    Omitted => ()
    Null => fields["lastModified"] = Json::null()
    Value(last_modified) => fields["lastModified"] = Json::string(last_modified)
  }
  match value.priority {
    Omitted => ()
    Null => fields["priority"] = Json::null()
    Value(priority) =>
      fields["priority"] = encode_finite_number(priority, path="priority")
  }
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_text_content_fields(
  fields : Map[String, Json],
  path~ : String,
  with_type : Bool,
) -> TextContent raise ProtocolDecodeError {
  let allowed = if with_type {
    ["type", "annotations", "text", "_meta"]
  } else {
    ["annotations", "text", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let annotations = decode_nullable_annotations(fields, path~)
  let text = protocol_required_string(fields, "text", path=path + ".text")
  let meta = protocol_meta(fields, path=path + "._meta")
  { annotations, text, meta, }
}

///|
/// Decode text content from a JSON value.
pub fn text_content_from_json(
  value : Json,
  path? : String = "text",
) -> TextContent raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_text_content_fields(fields, path~, false)
}

///|
/// Encode text content as a JSON object.
pub fn text_content_to_json(
  value : TextContent,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  put_nullable_annotations(fields, value.annotations)
  fields["text"] = Json::string(value.text)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_image_content_fields(
  fields : Map[String, Json],
  path~ : String,
  with_type : Bool,
) -> ImageContent raise ProtocolDecodeError {
  let allowed = if with_type {
    ["type", "annotations", "data", "mimeType", "uri", "_meta"]
  } else {
    ["annotations", "data", "mimeType", "uri", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let annotations = decode_nullable_annotations(fields, path~)
  let data = protocol_required_string(fields, "data", path=path + ".data")
  let data = protocol_validate_base64(data, field_path=path + ".data")
  let mime_type = protocol_required_string(
    fields,
    "mimeType",
    path=path + ".mimeType",
  )
  let uri = protocol_nullable_string(fields, "uri", path=path + ".uri")
  let meta = protocol_meta(fields, path=path + "._meta")
  { annotations, data, mime_type, uri, meta, }
}

///|
/// Decode image content from a JSON value.
pub fn image_content_from_json(
  value : Json,
  path? : String = "image",
) -> ImageContent raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_image_content_fields(fields, path~, false)
}

///|
/// Encode image content as a JSON object.
pub fn image_content_to_json(
  value : ImageContent,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  put_nullable_annotations(fields, value.annotations)
  fields["data"] = Json::string(
    protocol_validate_base64(value.data, field_path="data"),
  )
  fields["mimeType"] = Json::string(value.mime_type)
  protocol_put_nullable(fields, "uri", value.uri, value => Json::string(value))
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_audio_content_fields(
  fields : Map[String, Json],
  path~ : String,
  with_type : Bool,
) -> AudioContent raise ProtocolDecodeError {
  let allowed = if with_type {
    ["type", "annotations", "data", "mimeType", "_meta"]
  } else {
    ["annotations", "data", "mimeType", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let annotations = decode_nullable_annotations(fields, path~)
  let data = protocol_required_string(fields, "data", path=path + ".data")
  let data = protocol_validate_base64(data, field_path=path + ".data")
  let mime_type = protocol_required_string(
    fields,
    "mimeType",
    path=path + ".mimeType",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { annotations, data, mime_type, meta, }
}

///|
/// Decode audio content from a JSON value.
pub fn audio_content_from_json(
  value : Json,
  path? : String = "audio",
) -> AudioContent raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_audio_content_fields(fields, path~, false)
}

///|
/// Encode audio content as a JSON object.
pub fn audio_content_to_json(
  value : AudioContent,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  put_nullable_annotations(fields, value.annotations)
  fields["data"] = Json::string(
    protocol_validate_base64(value.data, field_path="data"),
  )
  fields["mimeType"] = Json::string(value.mime_type)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_resource_link_fields(
  fields : Map[String, Json],
  path~ : String,
  with_type : Bool,
) -> ResourceLink raise ProtocolDecodeError {
  let allowed = if with_type {
    [
      "type", "annotations", "description", "mimeType", "name", "size", "title",
      "uri", "_meta",
    ]
  } else {
    [
      "annotations", "description", "mimeType", "name", "size", "title", "uri", "_meta",
    ]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let annotations = decode_nullable_annotations(fields, path~)
  let description = protocol_nullable_string(
    fields,
    "description",
    path=path + ".description",
  )
  let mime_type = protocol_nullable_string(
    fields,
    "mimeType",
    path=path + ".mimeType",
  )
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let size : ProtocolNullable[Int64] = match protocol_field(fields, "size") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(protocol_decode_int64(value, path=path + ".size"))
  }
  let title = protocol_nullable_string(fields, "title", path=path + ".title")
  let uri = protocol_required_string(fields, "uri", path=path + ".uri")
  let meta = protocol_meta(fields, path=path + "._meta")
  { annotations, description, mime_type, name, size, title, uri, meta, }
}

///|
/// Decode a resource link from a JSON value.
pub fn resource_link_from_json(
  value : Json,
  path? : String = "resource_link",
) -> ResourceLink raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_resource_link_fields(fields, path~, false)
}

///|
/// Encode a resource link as a JSON object.
pub fn resource_link_to_json(
  value : ResourceLink,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  put_nullable_annotations(fields, value.annotations)
  protocol_put_nullable(fields, "description", value.description, value => {
    Json::string(value)
  })
  protocol_put_nullable(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  fields["name"] = Json::string(value.name)
  match value.size {
    Omitted => ()
    Null => fields["size"] = Json::null()
    Value(size) => fields["size"] = size.to_json()
  }
  protocol_put_nullable(fields, "title", value.title, value => {
    Json::string(value)
  })
  fields["uri"] = Json::string(value.uri)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_text_resource_contents_fields(
  fields : Map[String, Json],
  path~ : String,
) -> TextResourceContents raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["mimeType", "text", "uri", "_meta"],
    prefix=path,
  )
  let mime_type = protocol_nullable_string(
    fields,
    "mimeType",
    path=path + ".mimeType",
  )
  let text = protocol_required_string(fields, "text", path=path + ".text")
  let uri = protocol_required_string(fields, "uri", path=path + ".uri")
  let meta = protocol_meta(fields, path=path + "._meta")
  { mime_type, text, uri, meta, }
}

///|
/// Decode text resource contents from a JSON value.
pub fn text_resource_contents_from_json(
  value : Json,
  path? : String = "resource",
) -> TextResourceContents raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_text_resource_contents_fields(fields, path~)
}

///|
/// Encode text resource contents as a JSON object.
pub fn text_resource_contents_to_json(
  value : TextResourceContents,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_nullable(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  fields["text"] = Json::string(value.text)
  fields["uri"] = Json::string(value.uri)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_blob_resource_contents_fields(
  fields : Map[String, Json],
  path~ : String,
) -> BlobResourceContents raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["blob", "mimeType", "uri", "_meta"],
    prefix=path,
  )
  let blob = protocol_required_string(fields, "blob", path=path + ".blob")
  let blob = protocol_validate_base64(blob, field_path=path + ".blob")
  let mime_type = protocol_nullable_string(
    fields,
    "mimeType",
    path=path + ".mimeType",
  )
  let uri = protocol_required_string(fields, "uri", path=path + ".uri")
  let meta = protocol_meta(fields, path=path + "._meta")
  { blob, mime_type, uri, meta, }
}

///|
/// Decode binary resource contents from a JSON value.
pub fn blob_resource_contents_from_json(
  value : Json,
  path? : String = "resource",
) -> BlobResourceContents raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_blob_resource_contents_fields(fields, path~)
}

///|
/// Encode binary resource contents as a JSON object.
pub fn blob_resource_contents_to_json(
  value : BlobResourceContents,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["blob"] = Json::string(
    protocol_validate_base64(value.blob, field_path="blob"),
  )
  protocol_put_nullable(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  fields["uri"] = Json::string(value.uri)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode an embedded resource payload from a JSON value.
pub fn embedded_resource_resource_from_json(
  value : Json,
  path? : String = "resource",
) -> EmbeddedResourceResource raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let has_text = fields.contains("text")
  let has_blob = fields.contains("blob")
  if has_text && has_blob {
    raise InvalidField(
      path~,
      reason="resource payload cannot contain both text and blob",
    )
  }
  if has_text {
    Text(decode_text_resource_contents_fields(fields, path~))
  } else if has_blob {
    Blob(decode_blob_resource_contents_fields(fields, path~))
  } else {
    raise InvalidField(
      path~,
      reason="resource payload must contain text or blob",
    )
  }
}

///|
/// Encode an embedded resource payload as a JSON object.
pub fn embedded_resource_resource_to_json(
  value : EmbeddedResourceResource,
) -> Json raise ProtocolDecodeError {
  match value {
    Text(value) => text_resource_contents_to_json(value)
    Blob(value) => blob_resource_contents_to_json(value)
  }
}

///|
fn decode_embedded_resource_fields(
  fields : Map[String, Json],
  path~ : String,
  with_type : Bool,
) -> EmbeddedResource raise ProtocolDecodeError {
  let allowed = if with_type {
    ["type", "annotations", "resource", "_meta"]
  } else {
    ["annotations", "resource", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let annotations = decode_nullable_annotations(fields, path~)
  let resource = match fields.get("resource") {
    Some(value) =>
      embedded_resource_resource_from_json(value, path=path + ".resource")
    None => raise MissingField(path=path + ".resource")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { annotations, resource, meta, }
}

///|
/// Decode an embedded resource from a JSON value.
pub fn embedded_resource_from_json(
  value : Json,
  path? : String = "resource",
) -> EmbeddedResource raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_embedded_resource_fields(fields, path~, false)
}

///|
/// Encode an embedded resource as a JSON object.
pub fn embedded_resource_to_json(
  value : EmbeddedResource,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  put_nullable_annotations(fields, value.annotations)
  fields["resource"] = embedded_resource_resource_to_json(value.resource)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn add_content_discriminator(value : Json, kind : String) -> Json {
  match value {
    Object(fields) => {
      fields["type"] = Json::string(kind)
      Json::object(fields)
    }
    _ => value
  }
}

///|
/// Encode one of the five stable ACP content block variants.
pub fn content_block_to_json(
  value : ContentBlock,
) -> Json raise ProtocolDecodeError {
  match value {
    Text(value) =>
      add_content_discriminator(text_content_to_json(value), "text")
    Image(value) =>
      add_content_discriminator(image_content_to_json(value), "image")
    Audio(value) =>
      add_content_discriminator(audio_content_to_json(value), "audio")
    ResourceLink(value) =>
      add_content_discriminator(resource_link_to_json(value), "resource_link")
    Resource(value) =>
      add_content_discriminator(embedded_resource_to_json(value), "resource")
  }
}

///|
fn content_block_from_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ContentBlock raise ProtocolDecodeError {
  let kind = protocol_required_string(fields, "type", path=path + ".type")
  match kind {
    "text" => Text(decode_text_content_fields(fields, path~, true))
    "image" => Image(decode_image_content_fields(fields, path~, true))
    "audio" => Audio(decode_audio_content_fields(fields, path~, true))
    "resource_link" =>
      ResourceLink(decode_resource_link_fields(fields, path~, true))
    "resource" => Resource(decode_embedded_resource_fields(fields, path~, true))
    _ => raise InvalidDiscriminator(path=path + ".type", value=kind)
  }
}

///|
/// Decode one of the five stable ACP content block variants.
pub fn content_block_from_json(
  value : Json,
  path? : String = "content",
) -> ContentBlock raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  content_block_from_fields(fields, path~)
}

///|
/// Decode a standard content wrapper.
fn content_from_fields(
  fields : Map[String, Json],
  path~ : String,
  with_type : Bool,
) -> Content raise ProtocolDecodeError {
  let allowed = if with_type {
    ["type", "content", "_meta"]
  } else {
    ["content", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let content = match fields.get("content") {
    Some(value) => content_block_from_json(value, path=path + ".content")
    None => raise MissingField(path=path + ".content")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { content, meta, }
}

///|
pub fn content_from_json(
  value : Json,
  path? : String = "content",
) -> Content raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  content_from_fields(fields, path~, false)
}

///|
/// Encode a standard content wrapper.
pub fn content_to_json(value : Content) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["content"] = content_block_to_json(value.content)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode a streamed content item.
fn content_chunk_from_fields(
  fields : Map[String, Json],
  path~ : String,
  with_session_update : Bool,
) -> ContentChunk raise ProtocolDecodeError {
  let allowed = if with_session_update {
    ["sessionUpdate", "content", "messageId", "_meta"]
  } else {
    ["content", "messageId", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let content = match fields.get("content") {
    Some(value) => content_block_from_json(value, path=path + ".content")
    None => raise MissingField(path=path + ".content")
  }
  let message_id = protocol_nullable_string(
    fields,
    "messageId",
    path=path + ".messageId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { content, message_id, meta, }
}

///|
pub fn content_chunk_from_json(
  value : Json,
  path? : String = "contentChunk",
) -> ContentChunk raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  content_chunk_from_fields(fields, path~, false)
}

///|
/// Encode a streamed content item.
pub fn content_chunk_to_json(
  value : ContentChunk,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["content"] = content_block_to_json(value.content)
  protocol_put_nullable(fields, "messageId", value.message_id, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
