const mongoose = require('mongoose');
const { Order, Expense, Product, InventoryTransaction, AuditLog, CashMovement, DayClose, Wastage, Purchase, RefundTransaction } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');

function businessDate(value = new Date()) {
  const d = new Date(value);
  const utc = d.getTime() + d.getTimezoneOffset() * 60000;
  return new Date(utc + 330 * 60000).toISOString().slice(0, 10);
}
function dayBounds(dateStr) {
  const [y,m,d] = dateStr.split('-').map(Number);
  const start = new Date(Date.UTC(y,m-1,d,0,0,0) - 330*60000);
  const end = new Date(Date.UTC(y,m-1,d,23,59,59,999) - 330*60000);
  return { start, end };
}
function n(v) { const x=Number(v); return Number.isFinite(x)?x:0; }
function r(v) { return Math.round((n(v)+Number.EPSILON)*100)/100; }
async function log(req, action, type, id, details={}) { try { await AuditLog.create({actor:req.user._id,action,entityType:type,entityId:id,details,ip:req.ip}); } catch (_) {} }

const getDaySummary = asyncHandler(async (req,res)=>{
  const date = req.query.date || businessDate(); const {start,end}=dayBounds(date);
  const [orders, expenses, shift, movements, refunds, pendingKitchen] = await Promise.all([
    Order.find({createdAt:{$gte:start,$lte:end},status:'completed'}),
    Expense.find({date:{$gte:start,$lte:end}}),
    DayClose.findOne({businessDate:date}),
    CashMovement.find({businessDate:date}).sort({createdAt:-1}),
    RefundTransaction.find({processedAt:{$gte:start,$lte:end}}),
    Order.countDocuments({createdAt:{$gte:start,$lte:end},orderSource:'qr',status:{$nin:['completed','voided']},kitchenStatus:{$ne:'served'}}),
  ]);
  const cashSales=r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.cash),0));
  const cashExpenses=r(expenses.filter(e=>e.paymentMethod==='CASH').reduce((s,e)=>s+n(e.amount),0));
  const cashRefunds=r(refunds.filter(x=>x.method==='CASH'||x.method==='MIXED').reduce((s,x)=>s+n(x.amount),0));
  const cashIn=r(movements.filter(x=>x.type==='IN').reduce((s,x)=>s+n(x.amount),0));
  const cashOut=r(movements.filter(x=>x.type==='OUT').reduce((s,x)=>s+n(x.amount),0));
  const upiRefunds=r(refunds.filter(x=>x.method==='UPI').reduce((s,x)=>s+n(x.amount),0));
  const opening=n(shift?.openingCash); const expected=r(opening+cashSales+cashIn-cashExpenses-cashOut-cashRefunds);
  res.json({success:true,data:{date, sales:r(orders.reduce((s,o)=>s+n(o.grandTotal),0)), orders:orders.length, cashSales, upi:r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.upi),0)), credit:r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.credit),0)), cashExpenses, cashIn, cashOut, openingCash:opening, expectedCash:expected, cashRefunds, upiRefunds, pendingKitchen, shift:shift||null, closed:shift?.status==='closed', expenses, movements}});
});

const openDay = asyncHandler(async(req,res)=>{
  const date=req.body.businessDate||businessDate();
  let day=await DayClose.findOne({businessDate:date});
  if(day?.status==='closed') throw new ApiError(409,'This business day is already closed.');
  const isNew=!day;
  if(!day) day=await DayClose.create({businessDate:date,openingCash:Math.max(0,n(req.body.openingCash)),openedBy:req.user._id});
  if(isNew) await CashMovement.create({type:'OPENING',amount:day.openingCash,reason:'Opening cash',recordedBy:req.user._id,businessDate:date});
  await log(req,'DAY_OPEN','DayClose',day._id,{openingCash:day.openingCash});
  res.status(201).json({success:true,data:day});
});

const closeDay = asyncHandler(async(req,res)=>{
  const date=req.body.businessDate||businessDate(); const {start,end}=dayBounds(date);
  const day=await DayClose.findOne({businessDate:date}); if(!day) throw new ApiError(400,'Open the business day first.');
  if(day.status==='closed') return res.json({success:true,data:day});
  const openCount = await Order.countDocuments({createdAt:{$gte:start,$lte:end},status:'open'});
  if (openCount > 0) throw new ApiError(409, `Cannot close the day while ${openCount} unpaid/open order(s) remain.`);
  const [orders,expenses,movements,refunds]=await Promise.all([
    Order.find({createdAt:{$gte:start,$lte:end},status:'completed'}), Expense.find({date:{$gte:start,$lte:end}}), CashMovement.find({businessDate:date}), RefundTransaction.find({processedAt:{$gte:start,$lte:end}})
  ]);
  day.cashSales=r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.cash),0));
  day.cashExpenses=r(expenses.filter(e=>e.paymentMethod==='CASH').reduce((s,e)=>s+n(e.amount),0));
  day.cashIn=r(movements.filter(x=>x.type==='IN').reduce((s,x)=>s+n(x.amount),0));
  day.cashOut=r(movements.filter(x=>x.type==='OUT').reduce((s,x)=>s+n(x.amount),0));
  const cashRefunds=r(refunds.filter(x=>x.method==='CASH'||x.method==='MIXED').reduce((s,x)=>s+n(x.amount),0));
  day.expectedCash=r(day.openingCash+day.cashSales+day.cashIn-day.cashExpenses-day.cashOut-cashRefunds);
  day.actualCash=Math.max(0,n(req.body.actualCash)); day.difference=r(day.actualCash-day.expectedCash); day.note=req.body.note; day.status='closed'; day.closedBy=req.user._id; day.closedAt=new Date(); await day.save();
  await log(req,'DAY_CLOSE','DayClose',day._id,{expectedCash:day.expectedCash,actualCash:day.actualCash,difference:day.difference});
  res.json({success:true,data:day});
});

const cashMovement = asyncHandler(async(req,res)=>{
  const type=req.body.type; if(!['IN','OUT'].includes(type)) throw new ApiError(400,'Cash movement type must be IN or OUT.');
  const amount=n(req.body.amount); if(amount<=0) throw new ApiError(400,'Amount must be greater than zero.');
  const date=req.body.businessDate||businessDate(); const day=await DayClose.findOne({businessDate:date}); if(day?.status==='closed') throw new ApiError(409,'Business day is closed.');
  const item=await CashMovement.create({type,amount,reason:req.body.reason,reference:req.body.reference,recordedBy:req.user._id,businessDate:date}); await log(req,'CASH_MOVEMENT','CashMovement',item._id,{type,amount}); res.status(201).json({success:true,data:item});
});

const createWastage = asyncHandler(async(req,res)=>{
  const date=businessDate(); const day=await DayClose.findOne({businessDate:date}); if(day?.status==='closed') throw new ApiError(409,'Business day is closed.');
  const qty=n(req.body.quantity); if(qty<=0) throw new ApiError(400,'Quantity must be greater than zero.');
  const session=await mongoose.startSession(); let item;
  try { await session.withTransaction(async()=>{
    const product=await Product.findOne({_id:req.body.productId,isDeleted:false,trackInventory:true}).session(session); if(!product) throw new ApiError(404,'Inventory product not found.');
    const updated=await Product.findOneAndUpdate({_id:product._id,stock:{$gte:qty}},{ $inc:{stock:-qty}},{new:true,session}); if(!updated) throw new ApiError(400,`Insufficient stock. Available: ${product.stock}.`);
    [item]=await Wastage.create([{product:product._id,quantity:qty,reason:req.body.reason,notes:req.body.notes,recordedBy:req.user._id}],{session});
    await InventoryTransaction.create([{product:product._id,type:'STOCK_OUT',quantity:-qty,stockAfter:updated.stock,reason:`Wastage: ${req.body.reason||'Other'}`,recordedBy:req.user._id}],{session});
  }); } finally { await session.endSession(); }
  await log(req,'WASTAGE_CREATE','Wastage',item._id,{quantity:qty}); res.status(201).json({success:true,data:await Wastage.findById(item._id).populate('product','name').populate('recordedBy','name')});
});
const listWastage=asyncHandler(async(req,res)=>{ const items=await Wastage.find({}).populate('product','name').populate('recordedBy','name').sort({createdAt:-1}).limit(300); res.json({success:true,data:items}); });

const createPurchase = asyncHandler(async(req,res)=>{
  const date=businessDate(); const day=await DayClose.findOne({businessDate:date}); if(day?.status==='closed') throw new ApiError(409,'Business day is closed.');
  if(!req.body.supplier || !Array.isArray(req.body.items) || !req.body.items.length) throw new ApiError(400,'Supplier and at least one item are required.');
  const session=await mongoose.startSession(); let purchase;
  try { await session.withTransaction(async()=>{
    const items=[]; let subtotal=0;
    for(const line of req.body.items){ const qty=n(line.quantity), cost=n(line.unitCost); if(!line.productId||qty<=0||cost<0) throw new ApiError(400,'Invalid purchase item.'); const p=await Product.findOne({_id:line.productId,isDeleted:false}).session(session); if(!p) throw new ApiError(404,'Purchase product not found.'); const total=r(qty*cost); subtotal=r(subtotal+total); items.push({product:p._id,name:p.name,quantity:qty,unitCost:cost,total}); await Product.updateOne({_id:p._id},{$inc:{stock:qty},$set:{costPrice:cost}},{session}); const updated=await Product.findById(p._id).session(session); await InventoryTransaction.create([{product:p._id,type:'STOCK_IN',quantity:qty,stockAfter:updated.stock,reason:`Purchase from ${req.body.supplier}`,recordedBy:req.user._id}],{session}); }
    const tax=r(req.body.tax); const total=r(subtotal+tax); const paymentStatus=req.body.paymentStatus||'paid'; const paidAmount=r(n(req.body.paidAmount)); if(!['paid','unpaid','partial'].includes(paymentStatus)) throw new ApiError(400,'Invalid purchase payment status.'); if(paymentStatus==='paid' && Math.abs(paidAmount-total)>0.01) throw new ApiError(400,'Paid purchase must have paidAmount equal to total.'); if(paymentStatus==='unpaid' && paidAmount!==0) throw new ApiError(400,'Unpaid purchase cannot have a paid amount.'); if(paymentStatus==='partial' && (paidAmount<=0 || paidAmount>=total)) throw new ApiError(400,'Partial purchase paidAmount must be greater than zero and less than total.'); [purchase]=await Purchase.create([{supplier:String(req.body.supplier).trim(),invoiceNumber:req.body.invoiceNumber,items,subtotal,tax,total,paymentStatus,paidAmount,date:req.body.date||new Date(),notes:req.body.notes,recordedBy:req.user._id}],{session});
  }); } finally { await session.endSession(); }
  await log(req,'PURCHASE_CREATE','Purchase',purchase._id,{total:purchase.total,supplier:purchase.supplier}); res.status(201).json({success:true,data:await Purchase.findById(purchase._id).populate('items.product','name')});
});
const listPurchases=asyncHandler(async(req,res)=>{ const items=await Purchase.find({}).populate('recordedBy','name').sort({date:-1}).limit(300); res.json({success:true,data:items}); });

const setDeliveryStatus=asyncHandler(async(req,res)=>{ const allowed=['new','preparing','ready','out_for_delivery','delivered','cancelled']; if(!allowed.includes(req.body.status)) throw new ApiError(400,'Invalid delivery status.'); const order=await Order.findById(req.params.id); if(!order) throw new ApiError(404,'Order not found.'); if(order.orderType!=='delivery') throw new ApiError(400,'Only delivery orders have delivery status.'); order.deliveryStatus=req.body.status; if(req.body.status==='preparing') order.kitchenStatus='preparing'; if(req.body.status==='ready') order.kitchenStatus='ready'; if(req.body.status==='delivered') order.kitchenStatus='served'; await order.save(); await log(req,'DELIVERY_STATUS','Order',order._id,{status:req.body.status}); res.json({success:true,data:order}); });

const getManagementOverview=asyncHandler(async(req,res)=>{ const date=req.query.date||businessDate(); const {start,end}=dayBounds(date); const [summary,lowStock,delivery,pending] = await Promise.all([DayClose.findOne({businessDate:date}),Product.countDocuments({isDeleted:false,trackInventory:true,$expr:{$lte:['$stock','$lowStockThreshold']}}),Order.countDocuments({createdAt:{$gte:start,$lte:end},orderType:'delivery',status:{$nin:['voided','completed']}}),Order.countDocuments({createdAt:{$gte:start,$lte:end},status:'open'})]); res.json({success:true,data:{date,lowStock,deliveryPending:delivery,openOrders:pending,day:summary}}); });
module.exports={getDaySummary,openDay,closeDay,cashMovement,createWastage,listWastage,createPurchase,listPurchases,setDeliveryStatus,getManagementOverview};
