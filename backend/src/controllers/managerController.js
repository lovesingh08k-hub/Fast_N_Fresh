const { Order, Expense, Product, InventoryTransaction, AuditLog, CashMovement, DayClose, RefundTransaction } = require('../models');
const { ApiError, asyncHandler } = require('../utils/apiError');
const { businessDate: istBusinessDate } = require('../utils/dateRanges');

function businessDate(value = new Date()) {
  return istBusinessDate(value);
}
function dayBounds(dateStr) {
  if (typeof dateStr !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) throw new ApiError(400, 'Date must be in YYYY-MM-DD format.');
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
  res.json({success:true,data:{date, sales:r(orders.reduce((s,o)=>s+n(o.grandTotal),0)), orders:orders.length, cashSales, upi:r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.upi),0)), credit:r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.credit),0)), card:r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.card),0)), online:r(orders.reduce((s,o)=>s+n(o.paymentBreakdown?.online),0)), cashExpenses, cashIn, cashOut, openingCash:opening, expectedCash:expected, cashRefunds, upiRefunds, pendingKitchen, shift:shift||null, closed:shift?.status==='closed', expenses, movements}});
});

const openDay = asyncHandler(async(req,res)=>{
  const date=req.body.businessDate||businessDate(); dayBounds(date);
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
  const openCount = await Order.countDocuments({createdAt:{$gte:start,$lte:end},status:{$in:['open','preparing','ready']}});
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
  const date=req.body.businessDate||businessDate(); dayBounds(date); const day=await DayClose.findOne({businessDate:date}); if(day?.status==='closed') throw new ApiError(409,'Business day is closed.');
  const item=await CashMovement.create({type,amount,reason:req.body.reason,reference:req.body.reference,recordedBy:req.user._id,businessDate:date}); await log(req,'CASH_MOVEMENT','CashMovement',item._id,{type,amount}); res.status(201).json({success:true,data:item});
});

const setDeliveryStatus=asyncHandler(async(req,res)=>{ const allowed=['new','preparing','ready','out_for_delivery','delivered','cancelled']; if(!allowed.includes(req.body.status)) throw new ApiError(400,'Invalid delivery status.'); const order=await Order.findById(req.params.id); if(!order) throw new ApiError(404,'Order not found.'); if(order.orderType!=='delivery') throw new ApiError(400,'Only delivery orders have delivery status.'); order.deliveryStatus=req.body.status; if(req.body.status==='preparing') order.kitchenStatus='preparing'; if(req.body.status==='ready') order.kitchenStatus='ready'; if(req.body.status==='delivered') order.kitchenStatus='served'; await order.save(); await log(req,'DELIVERY_STATUS','Order',order._id,{status:req.body.status}); res.json({success:true,data:order}); });

const getManagementOverview=asyncHandler(async(req,res)=>{ const date=req.query.date||businessDate(); const {start,end}=dayBounds(date); const [summary,lowStock,delivery,pending] = await Promise.all([DayClose.findOne({businessDate:date}),Product.countDocuments({isDeleted:false,trackInventory:true,$expr:{$lte:['$stock','$lowStockThreshold']}}),Order.countDocuments({createdAt:{$gte:start,$lte:end},orderType:'delivery',status:{$nin:['voided','completed']}}),Order.countDocuments({createdAt:{$gte:start,$lte:end},status:'open'})]); res.json({success:true,data:{date,lowStock,deliveryPending:delivery,openOrders:pending,day:summary}}); });
module.exports={getDaySummary,openDay,closeDay,cashMovement,setDeliveryStatus,getManagementOverview};
