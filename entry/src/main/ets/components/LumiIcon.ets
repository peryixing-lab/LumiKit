export function iconResource(name: string, muted: boolean = false): Resource {
  switch (name) {
    case 'tool-pdf-compress': return $r('app.media.ic_tool_pdf_compress');
    case 'tool-pdf-edit': return $r('app.media.ic_tool_pdf_edit');
    case 'tool-image-ocr': return $r('app.media.ic_tool_image_ocr');
    case 'tool-pdf-merge': return $r('app.media.ic_tool_pdf_merge');
    case 'tool-pdf-split': return $r('app.media.ic_tool_pdf_split');
    case 'tool-pdf-extract': return $r('app.media.ic_tool_pdf_extract');
    case 'tool-pdf-images': return $r('app.media.ic_tool_pdf_images');
    case 'tool-images-pdf': return $r('app.media.ic_tool_images_pdf');
    case 'tool-image-compress': return $r('app.media.ic_tool_image_compress');
    case 'tool-image-convert': return $r('app.media.ic_tool_image_convert');
    case 'tool-csv-json': return $r('app.media.ic_tool_csv_json');
    case 'tool-json-csv': return $r('app.media.ic_tool_json_csv');
    case 'tool-text-convert': return $r('app.media.ic_tool_text_convert');
    case 'tool-inventory': return $r('app.media.ic_tool_inventory');
    case 'tool-forms': return $r('app.media.ic_tool_forms');
    case 'tool-json': return $r('app.media.ic_tool_json');
    case 'tool-base64': return $r('app.media.ic_tool_base64');
    case 'tool-url': return $r('app.media.ic_tool_url');
    case 'tool-timestamp': return $r('app.media.ic_tool_timestamp');
    case 'tool-hash': return $r('app.media.ic_tool_hash');
    case 'tool-uuid': return $r('app.media.ic_tool_uuid');
    case 'tool-color': return $r('app.media.ic_tool_color');
    case 'tool-diff': return $r('app.media.ic_tool_diff');
    case 'tool-regex': return $r('app.media.ic_tool_regex');
    case 'tool-markdown': return $r('app.media.ic_tool_markdown');
    case 'tool-analytics': return $r('app.media.ic_tool_analytics');
    case 'dock-home': return muted ? $r('app.media.ic_dock_home_muted') : $r('app.media.ic_dock_home');
    case 'dock-tools': return muted ? $r('app.media.ic_dock_tools_muted') : $r('app.media.ic_dock_tools');
    case 'dock-history': return muted ? $r('app.media.ic_dock_history_muted') : $r('app.media.ic_dock_history');
    case 'dock-profile': return muted ? $r('app.media.ic_dock_profile_muted') : $r('app.media.ic_dock_profile');
    case 'home': return muted ? $r('app.media.ic_home_muted') : $r('app.media.ic_home');
    case 'tools': return muted ? $r('app.media.ic_tools_muted') : $r('app.media.ic_tools');
    case 'history': return muted ? $r('app.media.ic_history_muted') : $r('app.media.ic_history');
    case 'profile': return muted ? $r('app.media.ic_profile_muted') : $r('app.media.ic_profile');
    case 'pdf': return muted ? $r('app.media.ic_pdf_muted') : $r('app.media.ic_pdf');
    case 'convert': return muted ? $r('app.media.ic_convert_muted') : $r('app.media.ic_convert');
    case 'inventory': return muted ? $r('app.media.ic_inventory_muted') : $r('app.media.ic_inventory');
    case 'forms': return muted ? $r('app.media.ic_forms_muted') : $r('app.media.ic_forms');
    case 'code': return muted ? $r('app.media.ic_code_muted') : $r('app.media.ic_code');
    case 'chart': return muted ? $r('app.media.ic_chart_muted') : $r('app.media.ic_chart');
    case 'image': return muted ? $r('app.media.ic_image_muted') : $r('app.media.ic_image');
    case 'clock': return muted ? $r('app.media.ic_clock_muted') : $r('app.media.ic_clock');
    case 'color': return muted ? $r('app.media.ic_color_muted') : $r('app.media.ic_color');
    case 'search': return muted ? $r('app.media.ic_search_muted') : $r('app.media.ic_search');
    case 'import': return muted ? $r('app.media.ic_import_muted') : $r('app.media.ic_import');
    case 'shield': return muted ? $r('app.media.ic_shield_muted') : $r('app.media.ic_shield');
    case 'star': return muted ? $r('app.media.ic_star_muted') : $r('app.media.ic_star');
    case 'chevron': return muted ? $r('app.media.ic_chevron_muted') : $r('app.media.ic_chevron');
    case 'plus': return muted ? $r('app.media.ic_plus_muted') : $r('app.media.ic_plus');
    case 'sun': return muted ? $r('app.media.ic_sun_muted') : $r('app.media.ic_sun');
    case 'folder': return muted ? $r('app.media.ic_folder_muted') : $r('app.media.ic_folder');
    case 'info': return muted ? $r('app.media.ic_info_muted') : $r('app.media.ic_info');
    case 'back': return muted ? $r('app.media.ic_back_muted') : $r('app.media.ic_back');
    default: return muted ? $r('app.media.ic_arrow_muted') : $r('app.media.ic_arrow');
  }
}

@Component
export struct LumiIcon {
  @Prop name: string = 'tools';
  @Prop iconSize: number = 24;
  @Prop muted: boolean = false;
  build() {
    Image(iconResource(this.name, this.muted)).width(this.iconSize).height(this.iconSize)
      .draggable(false).accessibilityLevel('no')
  }
}
