const mongoose = require('mongoose');
const userRef = require('./userRef');

// One "export, then clean up" cycle of old records (see archiveController).
// Deleting is only allowed for a cut-off date whose export was downloaded.
const archiveRunSchema = new mongoose.Schema(
  {
    before: { type: Date, required: true }, // records created before this are archived
    status: { type: String, enum: ['exported', 'purged'], default: 'exported' },
    counts: { type: mongoose.Schema.Types.Mixed, default: {} },
    exportedBy: { type: mongoose.Schema.Types.ObjectId, ref: userRef },
    exportedAt: { type: Date, default: Date.now },
    purgedBy: { type: mongoose.Schema.Types.ObjectId, ref: userRef },
    purgedAt: { type: Date },
  },
  { timestamps: true }
);

archiveRunSchema.index({ createdAt: -1 });

module.exports = mongoose.model('ArchiveRun', archiveRunSchema);
