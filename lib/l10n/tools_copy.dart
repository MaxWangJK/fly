import 'package:flutter/widgets.dart';

import 'fly_localizations.dart';

const toolsEnglish = <String, String>{
  "确认": "Confirm",
  "取消": "Cancel",
  "确定": "OK",
  "保存": "Save",
  "名称": "Name",
  "类型": "Type",
  "添加货物": "Add cargo",
  "复制规格": "Duplicate specification",
  "编辑货物": "Edit cargo",
  "包装": "Package",
  "托盘": "Pallet",
  "木箱": "Crate",
  "门扇": "Door panel",
  "自定义": "Custom",
  "高度": "Height",
  "宽度": "Width",
  "厚度": "Thickness",
  "长度": "Length",
  "单件重量": "Unit weight",
  "每节装箱数": "Quantity per section",
  "选填": "Optional",
  "保存规格": "Save specification",
  "请填写有效名称、正数尺寸和重量；每节装箱数可留空。": "Enter a name, positive dimensions and a non-negative weight. Section quantity is optional.",
  "添加集装箱": "Add container",
  "编辑集装箱": "Edit container",
  "内部长度": "Internal length",
  "内部宽度": "Internal width",
  "内部高度": "Internal height",
  "最大货重": "Maximum payload",
  "请填写名称及大于 0 的尺寸和载重": "Enter a name, positive dimensions and payload.",
  "当前方案有未保存的修改。确定切换并放弃这些修改？":
      "This plan has unsaved changes. Switch and discard them?",
  "切换": "Switch",
  "集装箱": "Containers",
  "编辑尺寸": "Edit dimensions",
  "恢复默认值": "Restore defaults",
  "保存的方案": "Saved plans",
  "暂无保存方案": "No saved plans",
  "打开方案": "Open plan",
  "编辑方案": "Edit plan",
  "重命名": "Rename",
  "重命名方案": "Rename plan",
  "删除方案": "Delete plan",
  "删除": "Delete",
  "收起": "Collapse",
  "更多 >": "More >",
  "货物": "Cargo",
  "编辑": "Edit",
  "更多": "More",
  "重新自动装柜将覆盖本节的手动位置。":
      "Recalculating will replace manual positions in this section.",
  "重新计算": "Recalculate",
  "保存方案": "Save plan",
  "方案已保存": "Plan saved",
  "未装货物处理": "Unloaded cargo",
  "返回调整": "Adjust settings",
  "计算待更新分节": "Recalculate pending sections",
  "确认保留未装数量": "Keep unloaded quantity",
  "已确认保留未装数量，请保存方案":
      "Unloaded quantity retained. Save the plan to keep this decision.",
  "截图已导出": "Screenshot exported",
  "已复制装柜结果": "Loading summary copied",
  "先计算待更新分节，再确认实际未装数量。不会自动修改您的设置数量。": "Recalculate pending sections before confirming unloaded quantities. Your requested quantities will not change.",
  "未装货物仍在计划中，但没有计入 3D 已装数量。可返回调整数量、尺寸、间距或分节；也可确认保留，安排其他柜次。确认不会强行把货物放入柜内。": "Unloaded cargo remains in the plan but is excluded from the 3D loaded count. Adjust quantities, dimensions or sections, or retain it for another container. Confirmation does not force cargo into the container.",
  "拖动空白平移 · Alt 拖动旋转 · 滚轮缩放 · Shift 拖动整体平移 · 拖动货物移动": "Drag background to pan · Alt+drag to rotate · Scroll to zoom · Shift+drag to pan · Drag cargo to move",
  "仅供装柜规划参考，请结合实际箱体、包装变形、装柜间隙、门尺寸及当地重量规定确认。": "Planning aid only. Confirm actual container and door dimensions, packaging deformation, clearances and local weight limits.",
  "请在纸箱尺寸中自行计入预留量": "Include any required clearance in package dimensions",
  "集装箱分节": "Container sections",
  "调整分节": "Edit sections",
  "实时计算": "Live layout",
  "选择货物": "Select cargo",
  "松开以添加货物": "Drop to add cargo",
  "+ 选择货物 / 拖放到本节": "+ Select cargo / drop into this section",
  "旧方案位置需复核，请检查分节边界或重新自动装柜。":
      "Review this older layout: check section boundaries or recalculate.",
  "整柜汇总": "Container summary",
  "部分设置待重新计算": "Some sections need recalculation",
  "已确认保留的未装数量仍需另行安排": "Retained unloaded cargo must be arranged separately",
  "⚠ 超出载重": "⚠ Payload exceeded",
  "有未保存的修改": "Unsaved changes",
  "分节剖面 · 面向货柜内部": "Section cross-section · Looking into container",
  "上方空间允许长度悬出最多1m，仅用于规划；需现场确认支撑与承重。": "Top space permits up to 1m length overhang for planning only. Confirm support and load capacity on site.",
  "尺寸为长 × 宽 × 高；宽或高不足50cm的空闲余隙不再提示装货。": "Dimensions: L × W × H. Empty gaps under 50cm wide or high are not offered for loading.",
  "小空间：保留已有分配，不再建议追加货物": "Small space: existing assignments retained; no additional cargo suggested",
  "+ 选择本空间货物": "+ Select cargo for this space",
  "原空间已变化，请删除此分配并重新选择空间": "The original space has changed. Remove this assignment and select a space again.",
  "重置视角": "Reset view",
  "顶部": "Top",
  "侧面": "Side",
  "正面": "Front",
  "撤销 Ctrl+Z": "Undo Ctrl+Z",
  "重做 Ctrl+Y": "Redo Ctrl+Y",
  "场景显示": "Scene options",
  "显示网格": "Show grid",
  "显示尺寸": "Show dimensions",
  "箱体透明度": "Container opacity",
  "显示所有节": "Show all sections",
  "复制装柜结果": "Copy loading summary",
  "导出 PNG 截图": "Export PNG",
  "降低 50mm": "Lower 50mm",
  "升高 50mm": "Raise 50mm",
  "转 X": "Rotate X",
  "转 Y": "Rotate Y",
  "转 Z": "Rotate Z",
  "恢复位置": "Restore position",
  "删除货物组": "Delete cargo group",
  "位置与边界、堆叠或其它货物冲突":
      "Position conflicts with boundaries, stacking rules or other cargo",
  "位置无效，已恢复原位置": "Invalid position. Original position restored.",
  "减少节数会移除末尾分节及其中货物，确定继续？":
      "Reducing sections removes trailing sections and their cargo. Continue?",
  "数量": "Quantity",
  "每排数量": "Units per row",
  "纵向排数（层）": "Rows (layers)",
  "理论本节": "Section capacity",
  "本空间上限": "Space capacity",
  "收起设置": "Hide settings",
  "摆放设置": "Placement",
  "⚠ 用户覆盖理论容量": "⚠ Capacity overridden",
  "平放": "Flat",
  "立放": "Upright",
  "侧放": "On side",
  "自动": "Auto",
  "靠左": "Left",
  "居中": "Center",
  "靠右": "Right",
  "放在底部": "On floor",
  "允许堆叠": "Stackable",
  "允许长度悬出≤1m": "Allow length overhang ≤1m",
  "每节长度必须大于 0": "Section lengths must be greater than 0",
  "应用": "Apply",
};

extension ToolsCopyContext on BuildContext {
  // Presentation only: packing logic and persisted identifiers retain their names.
  String toolsSpaceName(String value) {
    if (l10n.isZh) return value;
    const names = {
      '左侧空间': 'Left space',
      '右侧空间': 'Right space',
      '上方空间': 'Top space',
      '货物上方空间': 'Space above cargo',
      '侧面剩余空间': 'Remaining side space',
    };
    final parts = value.split(' · ');
    final translated = names[parts.last];
    if (translated != null) {
      return [...parts.take(parts.length - 1), translated].join(' · ');
    }
    if (value == '第一节') return 'Section 1';
    final section = RegExp(r'^第(\d+)节$').firstMatch(value);
    return section == null ? value : 'Section ${section.group(1)}';
  }

  String toolsCopy(String value) =>
      l10n.isZh ? value : toolsEnglish[value] ?? value;
}
