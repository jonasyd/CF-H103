import 'neo_utils.dart';

/// ------------------------------------------------------------
/// MODELOS UI / DOMINIO
/// ------------------------------------------------------------

class DepositOption {
  final String uuid;
  final String label;

  const DepositOption({required this.uuid, required this.label});

  // 1. De Map (JSON) a Objeto DepositOption
  // Se usa factory para crear una nueva instancia a partir de un mapa
  factory DepositOption.fromJson(Map<String, dynamic> json) {
    return DepositOption(
      uuid: json['uuid'] as String? ?? '',
      label: json['label'] as String? ?? 'Sin nombre',
    );
  }

  // 2. De Objeto DepositOption a Map (JSON)
  // Esto es lo que jsonEncode llamará internamente
  Map<String, dynamic> toJson() {
    return {'uuid': uuid, 'label': label};
  }
}

// Definición de la constante reutilizable (puedes moverla a un archivo de constantes si prefieres)
const List<DepositOption> defaultDepositOptions = [
  DepositOption(
    uuid: 'CAFEBABE1234567890C00L', // 22 caracteres
    label: 'CONFIGURE LA LISTA DE DEPOSITOS',
  ),
  DepositOption(
    uuid: 'BAADF00D9876543210BEEF', // 22 caracteres
    label: 'CONFIGURE AQUÍ LA LISTA DE DEPOSITOS',
  ),
];

class SearchImage {
  final bool hasImage;
  final SearchImageUrls? urls;

  SearchImage({required this.hasImage, required this.urls});

  factory SearchImage.fromJson(Map<String, dynamic> json) {
    return SearchImage(
      hasImage: asBool(json['hasImage']),
      urls: json['urls'] == null
          ? null
          : SearchImageUrls.fromJson(asMap(json['urls'])),
    );
  }

  String? get thumbUrl => hasImage ? urls?.thumb : null;
  String? get cardUrl => hasImage ? urls?.card : null;
}

class SearchImageUrls {
  final String thumb;
  final String card;

  SearchImageUrls({required this.thumb, required this.card});

  factory SearchImageUrls.fromJson(Map<String, dynamic> json) {
    return SearchImageUrls(
      thumb: asString(json['thumb']),
      card: asString(json['card']),
    );
  }
}

class ModelImage {
  final bool hasImage;
  final ModelImageUrls? urls;

  ModelImage({required this.hasImage, required this.urls});

  factory ModelImage.fromJson(Map<String, dynamic> json) {
    return ModelImage(
      hasImage: asBool(json['hasImage']),
      urls: json['urls'] == null
          ? null
          : ModelImageUrls.fromJson(asMap(json['urls'])),
    );
  }

  String? get thumbUrl => hasImage ? urls?.thumb : null;
  String? get cardUrl => hasImage ? urls?.card : null;
  String? get detailUrl => hasImage ? urls?.detail : null;
}

class ModelImageUrls {
  final String thumb;
  final String card;
  final String detail;

  ModelImageUrls({
    required this.thumb,
    required this.card,
    required this.detail,
  });

  factory ModelImageUrls.fromJson(Map<String, dynamic> json) {
    return ModelImageUrls(
      thumb: asString(json['thumb']),
      card: asString(json['card']),
      detail: asString(json['detail']),
    );
  }
}

class ModelSummary {
  final String modelUuid;
  final String modelCode;
  final String modelDescription;
  final String season;
  final SearchImage image;
  final PriceSummary priceSummary;
  final StockSummary stockSummary;
  final List<ColorSummaryItem> colors;

  ModelSummary({
    required this.modelUuid,
    required this.modelCode,
    required this.modelDescription,
    required this.season,
    required this.image,
    required this.priceSummary,
    required this.stockSummary,
    required this.colors,
  });

  factory ModelSummary.fromJson(Map<String, dynamic> json) {
    final colorsSummary = asMap(json['colorsSummary']);
    final colorItems = asList(
      colorsSummary['items'],
    ).map((e) => ColorSummaryItem.fromJson(asMap(e))).toList();

    return ModelSummary(
      modelUuid: asString(json['modelUuid']),
      modelCode: asString(json['modelCode']),
      modelDescription: asString(json['modelDescription']),
      season: asString(json['season']),
      image: SearchImage.fromJson(asMap(json['image'])),
      priceSummary: PriceSummary.fromJson(asMap(json['priceSummary'])),
      stockSummary: StockSummary.fromJson(asMap(json['stockSummary'])),
      colors: colorItems,
    );
  }
}

class PriceSummary {
  final double minPrice;
  final double maxPrice;
  final bool sameAcrossVariants;

  PriceSummary({
    required this.minPrice,
    required this.maxPrice,
    required this.sameAcrossVariants,
  });

  factory PriceSummary.fromJson(Map<String, dynamic> json) {
    return PriceSummary(
      minPrice: asDouble(json['minPrice']),
      maxPrice: asDouble(json['maxPrice']),
      sameAcrossVariants: asBool(json['sameAcrossVariants']),
    );
  }
}

class StockSummary {
  final int totalStock;
  final int totalTransit;
  final String status;

  StockSummary({
    required this.totalStock,
    required this.totalTransit,
    required this.status,
  });

  factory StockSummary.fromJson(Map<String, dynamic> json) {
    return StockSummary(
      totalStock: asInt(json['totalStock']),
      totalTransit: asInt(json['totalTransit']),
      status: asString(json['status']),
    );
  }
}

class ColorSummaryItem {
  final String code;
  final String description;

  ColorSummaryItem({required this.code, required this.description});

  factory ColorSummaryItem.fromJson(Map<String, dynamic> json) {
    return ColorSummaryItem(
      code: asString(json['code']),
      description: asString(json['description']),
    );
  }
}

class ModelDetail {
  final String modelUuid;
  final String modelCode;
  final String modelDescription;
  final String season;
  final ModelImage image;
  final String depositUuid;
  final int lowStockMax;
  final PriceSummary priceSummary;
  final SelectionContext? selectionContext;
  final List<ModelColor> colors;

  ModelDetail({
    required this.modelUuid,
    required this.modelCode,
    required this.modelDescription,
    required this.season,
    required this.image,
    required this.depositUuid,
    required this.lowStockMax,
    required this.priceSummary,
    required this.selectionContext,
    required this.colors,
  });

  factory ModelDetail.fromJson(Map<String, dynamic> json) {
    return ModelDetail(
      modelUuid: asString(json['modelUuid']),
      modelCode: asString(json['modelCode']),
      modelDescription: asString(json['modelDescription']),
      season: asString(json['season']),
      image: ModelImage.fromJson(asMap(json['image'])),
      depositUuid: asString(asMap(json['deposit'])['uuid']),
      lowStockMax: asInt(asMap(json['stockRules'])['lowStockMax']),
      priceSummary: PriceSummary.fromJson(asMap(json['priceSummary'])),
      selectionContext: json['selectionContext'] == null
          ? null
          : SelectionContext.fromJson(asMap(json['selectionContext'])),
      colors: asList(
        json['colors'],
      ).map((e) => ModelColor.fromJson(asMap(e))).toList(),
    );
  }
}

class SelectionContext {
  final String matchedBy;
  final String barcode;
  final String articleUuid;
  final String selectedColorCode;
  final String selectedSizeCode;

  SelectionContext({
    required this.matchedBy,
    required this.barcode,
    required this.articleUuid,
    required this.selectedColorCode,
    required this.selectedSizeCode,
  });

  factory SelectionContext.fromJson(Map<String, dynamic> json) {
    return SelectionContext(
      matchedBy: asString(json['matchedBy']),
      barcode: asString(json['barcode']),
      articleUuid: asString(json['articleUuid']),
      selectedColorCode: asString(json['selectedColorCode']),
      selectedSizeCode: asString(json['selectedSizeCode']),
    );
  }
}

class ModelColor {
  final String code;
  final String description;
  final int rfidCode;
  final List<ArticleVariant> sizes;

  ModelColor({
    required this.code,
    required this.description,
    required this.rfidCode,
    required this.sizes,
  });

  factory ModelColor.fromJson(Map<String, dynamic> json) {
    return ModelColor(
      code: asString(json['code']),
      description: asString(json['description']),
      rfidCode: asInt(json['rfidCode']),
      sizes: asList(
        json['sizes'],
      ).map((e) => ArticleVariant.fromJson(asMap(e))).toList(),
    );
  }
}

class ArticleVariant {
  final String articleUuid;
  final String barcode;
  final String articleDescription;
  final SizeInfo size;
  final VariantStock stock;
  final double price;
  final bool selectable;

  ArticleVariant({
    required this.articleUuid,
    required this.barcode,
    required this.articleDescription,
    required this.size,
    required this.stock,
    required this.price,
    required this.selectable,
  });

  factory ArticleVariant.fromJson(Map<String, dynamic> json) {
    return ArticleVariant(
      articleUuid: asString(json['articleUuid']),
      barcode: asString(json['barcode']),
      articleDescription: asString(json['articleDescription']),
      size: SizeInfo.fromJson(asMap(json['size'])),
      stock: VariantStock.fromJson(asMap(json['stock'])),
      price: asDouble(json['price']),
      selectable: asBool(json['selectable']),
    );
  }
}

class SizeInfo {
  final String code;
  final String description;
  final int rfidCode;

  SizeInfo({
    required this.code,
    required this.description,
    required this.rfidCode,
  });

  factory SizeInfo.fromJson(Map<String, dynamic> json) {
    return SizeInfo(
      code: asString(json['code']),
      description: asString(json['description']),
      rfidCode: asInt(json['rfidCode']),
    );
  }
}

class VariantStock {
  final int current;
  final int transit;
  final int remote;
  final int replicatedRemote;
  final String status;

  VariantStock({
    required this.current,
    required this.transit,
    required this.remote,
    required this.replicatedRemote,
    required this.status,
  });

  factory VariantStock.fromJson(Map<String, dynamic> json) {
    return VariantStock(
      current: asInt(json['current']),
      transit: asInt(json['transit']),
      remote: asInt(json['remote']),
      replicatedRemote: asInt(json['replicatedRemote']),
      status: asString(json['status']),
    );
  }
}

/// ------------------------------------------------------------
/// API
/// ------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() {
    if (statusCode == null) return message;
    return 'HTTP $statusCode - $message';
  }
}
