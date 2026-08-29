///|
/// Kind of file content represented by a diff change, with the schema's open
/// fallback.
pub(all) enum ExperimentalV2DiffFileType {
  DiffFileTypeText
  DiffFileTypeBinary
  DiffFileTypeDirectory
  DiffFileTypeSymlink
  DiffFileTypeExtension(tag~ : String)
  DiffFileTypeFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_diff_file_type(
  value : Json,
  path? : String = "fileType",
) -> ExperimentalV2DiffFileType raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "text" => DiffFileTypeText
    "binary" => DiffFileTypeBinary
    "directory" => DiffFileTypeDirectory
    "symlink" => DiffFileTypeSymlink
    _ =>
      if tag.has_prefix("_") {
        DiffFileTypeExtension(tag~)
      } else {
        DiffFileTypeFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_diff_file_type(
  value : ExperimentalV2DiffFileType,
) -> Json {
  match value {
    DiffFileTypeText => Json::string("text")
    DiffFileTypeBinary => Json::string("binary")
    DiffFileTypeDirectory => Json::string("directory")
    DiffFileTypeSymlink => Json::string("symlink")
    DiffFileTypeExtension(tag~) => Json::string(tag)
    DiffFileTypeFuture(raw~) => Json::string(raw)
  }
}

///|
/// Text patch format used by a diff patch, with the schema's open fallback.
/// `git_patch` is the only ACP-defined value.
pub(all) enum ExperimentalV2DiffPatchFormat {
  DiffPatchFormatGitPatch
  DiffPatchFormatExtension(tag~ : String)
  DiffPatchFormatFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_diff_patch_format(
  value : Json,
  path? : String = "format",
) -> ExperimentalV2DiffPatchFormat raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "git_patch" => DiffPatchFormatGitPatch
    _ =>
      if tag.has_prefix("_") {
        DiffPatchFormatExtension(tag~)
      } else {
        DiffPatchFormatFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_diff_patch_format(
  value : ExperimentalV2DiffPatchFormat,
) -> Json {
  match value {
    DiffPatchFormatGitPatch => Json::string("git_patch")
    DiffPatchFormatExtension(tag~) => Json::string(tag)
    DiffPatchFormatFuture(raw~) => Json::string(raw)
  }
}

///|
/// Renderable patch text and its format.
pub(all) struct ExperimentalV2DiffPatch {
  format : ExperimentalV2DiffPatchFormat
  text : String
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_diff_patch(
  value : Json,
  path? : String = "patch",
) -> ExperimentalV2DiffPatch raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["format", "text"], prefix=path)
  let format = experimental_v2_decode_diff_patch_format(
    experimental_v2_required(fields, "format", path=path + ".format"),
    path=path + ".format",
  )
  let text = experimental_v2_decode_string(
    experimental_v2_required(fields, "text", path=path + ".text"),
    path=path + ".text",
  )
  { format, text, }
}

///|
pub fn experimental_v2_encode_diff_patch(
  value : ExperimentalV2DiffPatch,
) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["format"] = experimental_v2_encode_diff_patch_format(value.format)
  fields["text"] = Json::string(value.text)
  Json::object(fields)
}

///|
fn experimental_v2_decode_diff_change_common(
  fields : Map[String, Json],
  path~ : String,
) -> (ExperimentalV2DiffFileType?, String?, Json?) raise ExperimentalV2DecodeError {
  let file_type = experimental_v2_decode_optional(
    fields,
    "fileType",
    path=path + ".fileType",
    (value, path) => experimental_v2_decode_diff_file_type(value, path~),
  )
  let mime_type = experimental_v2_decode_optional(
    fields,
    "mimeType",
    path=path + ".mimeType",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  (file_type, mime_type, meta)
}

///|
/// Operation metadata for add, delete, and modify changes.
pub(all) struct ExperimentalV2DiffPathChange {
  path : String
  file_type : ExperimentalV2DiffFileType?
  mime_type : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_diff_path_change(
  value : Json,
  path? : String = "change",
) -> ExperimentalV2DiffPathChange raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["operation", "path", "fileType", "mimeType", "_meta"],
    prefix=path,
  )
  let change_path = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "path", path=path + ".path"),
      path=path + ".path",
    ),
    field_path=path + ".path",
  )
  let (file_type, mime_type, meta) = experimental_v2_decode_diff_change_common(
    fields,
    path~,
  )
  { path: change_path, file_type, mime_type, meta, }
}

///|
pub fn experimental_v2_encode_diff_path_change(
  value : ExperimentalV2DiffPathChange,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json::string(
    experimental_v2_validate_absolute_path(value.path, field_path="path"),
  )
  experimental_v2_put_optional(fields, "fileType", value.file_type, value => {
    experimental_v2_encode_diff_file_type(value)
  })
  experimental_v2_put_optional(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Operation metadata for move and copy changes.
pub(all) struct ExperimentalV2DiffPathPairChange {
  old_path : String
  path : String
  file_type : ExperimentalV2DiffFileType?
  mime_type : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_diff_path_pair_change(
  value : Json,
  path? : String = "change",
) -> ExperimentalV2DiffPathPairChange raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["operation", "oldPath", "path", "fileType", "mimeType", "_meta"],
    prefix=path,
  )
  let old_path = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "oldPath", path=path + ".oldPath"),
      path=path + ".oldPath",
    ),
    field_path=path + ".oldPath",
  )
  let change_path = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "path", path=path + ".path"),
      path=path + ".path",
    ),
    field_path=path + ".path",
  )
  let (file_type, mime_type, meta) = experimental_v2_decode_diff_change_common(
    fields,
    path~,
  )
  { old_path, path: change_path, file_type, mime_type, meta, }
}

///|
pub fn experimental_v2_encode_diff_path_pair_change(
  value : ExperimentalV2DiffPathPairChange,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["oldPath"] = Json::string(
    experimental_v2_validate_absolute_path(value.old_path, field_path="oldPath"),
  )
  fields["path"] = Json::string(
    experimental_v2_validate_absolute_path(value.path, field_path="path"),
  )
  experimental_v2_put_optional(fields, "fileType", value.file_type, value => {
    experimental_v2_encode_diff_file_type(value)
  })
  experimental_v2_put_optional(fields, "mimeType", value.mime_type, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The five known v2 diff change operations.
pub(all) enum ExperimentalV2DiffChangeKnown {
  ChangeAdd(ExperimentalV2DiffPathChange)
  ChangeDelete(ExperimentalV2DiffPathChange)
  ChangeModify(ExperimentalV2DiffPathChange)
  ChangeMove(ExperimentalV2DiffPathPairChange)
  ChangeCopy(ExperimentalV2DiffPathPairChange)
} derive(Eq, Debug)

///|
/// One file-level change described by a diff.  The schema has an open
/// fallback: `_`-prefixed operations are implementation extensions and other
/// unknown operations are future values; both keep their raw object.
pub type ExperimentalV2DiffChange = ExperimentalV2Open[
  ExperimentalV2DiffChangeKnown,
]

///|
pub fn experimental_v2_decode_diff_change(
  value : Json,
  path? : String = "change",
) -> ExperimentalV2DiffChange raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="operation",
    ["add", "delete", "modify", "move", "copy"],
    (tag, payload) => {
      match tag {
        "add" =>
          ChangeAdd(experimental_v2_decode_diff_path_change(payload, path~))
        "delete" =>
          ChangeDelete(experimental_v2_decode_diff_path_change(payload, path~))
        "modify" =>
          ChangeModify(experimental_v2_decode_diff_path_change(payload, path~))
        "move" =>
          ChangeMove(
            experimental_v2_decode_diff_path_pair_change(payload, path~),
          )
        "copy" =>
          ChangeCopy(
            experimental_v2_decode_diff_path_pair_change(payload, path~),
          )
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".operation", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_diff_change(
  value : ExperimentalV2DiffChange,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="operation", known => {
    match known {
      ChangeAdd(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_diff_path_change(value),
          tag_key="operation",
          tag="add",
        )
      ChangeDelete(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_diff_path_change(value),
          tag_key="operation",
          tag="delete",
        )
      ChangeModify(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_diff_path_change(value),
          tag_key="operation",
          tag="modify",
        )
      ChangeMove(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_diff_path_pair_change(value),
          tag_key="operation",
          tag="move",
        )
      ChangeCopy(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_diff_path_pair_change(value),
          tag_key="operation",
          tag="copy",
        )
    }
  })
}

///|
/// File changes produced by a tool call.  `changes` is authoritative for
/// affected absolute paths and operations; `patch` optionally carries
/// renderable text for some or all of those changes.  Patch/changes
/// consistency is the caller's contract; it is not machine-checkable here.
pub(all) struct ExperimentalV2Diff {
  changes : Array[ExperimentalV2DiffChange]
  patch : ExperimentalV2DiffPatch?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_diff(
  value : Json,
  path? : String = "diff",
) -> ExperimentalV2Diff raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "changes", "patch", "_meta"],
    prefix=path,
  )
  let changes = experimental_v2_decode_array(
    experimental_v2_required(fields, "changes", path=path + ".changes"),
    path=path + ".changes",
    (item, item_path) => {
      experimental_v2_decode_diff_change(item, path=item_path)
    },
  )
  let patch = experimental_v2_decode_optional(
    fields,
    "patch",
    path=path + ".patch",
    (value, path) => experimental_v2_decode_diff_patch(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { changes, patch, meta, }
}

///|
pub fn experimental_v2_encode_diff(
  value : ExperimentalV2Diff,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["changes"] = experimental_v2_encode_array(
    value.changes,
    experimental_v2_encode_diff_change,
  )
  experimental_v2_put_optional(fields, "patch", value.patch, value => {
    experimental_v2_encode_diff_patch(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
