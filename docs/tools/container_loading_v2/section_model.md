# 分节数据模型

ContainerSection：id、planId、index、name、startXmm、lengthMm、createdAt、updatedAt。X 表示集装箱长度方向，Y 表示宽度，Z 表示高度，单位统一 mm。

分节必须从 X=0 连续排列，长度必须正数，合计不得超过箱长。余量显示为未分配区域，不平均摊入分节。

SectionCargoEntry：id、sectionId、cargoPackageId、cargoSnapshot、quantity、orientation、placeOnBottom、allowStack、horizontalPlacement、manualQuantityOverride、colorOverride 及时间。

CargoGroup 增加 sectionId、entryId、needsReview、allowStack。它只保存真实坐标和几何数据，界面负责重新生成场景。
