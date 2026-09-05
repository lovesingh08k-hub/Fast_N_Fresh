const mongoose = require('mongoose');

// Generic atomic counter, used to generate safe sequential bill numbers
// (avoids duplicate order numbers under concurrent requests).
const counterSchema = new mongoose.Schema({
  _id: { type: String, required: true }, // e.g. 'orderNumber'
  seq: { type: Number, default: 0 },
});

counterSchema.statics.getNextSequence = async function getNextSequence(name) {
  const result = await this.findByIdAndUpdate(
    name,
    { $inc: { seq: 1 } },
    { new: true, upsert: true }
  );
  return result.seq;
};

module.exports = mongoose.model('Counter', counterSchema);
