const mongoose = require('mongoose');

// Generic atomic counter, used to generate safe sequential bill numbers
// (avoids duplicate order numbers under concurrent requests).
const counterSchema = new mongoose.Schema({
  _id: { type: String, required: true }, // e.g. 'orderNumber'
  seq: { type: Number, default: 0 },
});

// Pass the transaction `session` so a retried or failed bill does not use
// up (skip) a number.
counterSchema.statics.getNextSequence = async function getNextSequence(name, session) {
  const result = await this.findByIdAndUpdate(
    name,
    { $inc: { seq: 1 } },
    { new: true, upsert: true, ...(session ? { session } : {}) }
  );
  return result.seq;
};

module.exports = mongoose.model('Counter', counterSchema);
