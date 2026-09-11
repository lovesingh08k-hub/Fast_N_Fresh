const mongoose = require('mongoose');

const imageAssetSchema = new mongoose.Schema(
  {
    data: { type: Buffer, required: true },
    contentType: { type: String, required: true },
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', default: null },
  },
  { timestamps: true }
);

module.exports = mongoose.model('ImageAsset', imageAssetSchema);
