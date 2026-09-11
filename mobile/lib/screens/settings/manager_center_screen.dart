import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/network/api_exception.dart';
import '../../services/manager_service.dart';
import '../../services/catalog_service.dart';
import '../../models/product.dart';

class ManagerCenterScreen extends StatefulWidget { const ManagerCenterScreen({super.key}); @override State<ManagerCenterScreen> createState()=>_ManagerCenterScreenState(); }
class _ManagerCenterScreenState extends State<ManagerCenterScreen> {
  final _service=ManagerService(); final _products=ProductService(); Map<String,dynamic>? _day; bool _loading=true; String? _error;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async { setState(()=>_loading=true); try{_day=await _service.day();_error=null;}catch(e){_error=_managerError(e);}finally{if(mounted)setState(()=>_loading=false);} }
  String _managerError(Object e){ if(e is ApiException){ switch(e.type){ case ApiErrorType.unauthorized: return 'Session expired. Please login again.'; case ApiErrorType.forbidden: return 'Manager/Admin access is required.'; case ApiErrorType.notFound: return 'Manager API is not available on the current backend.'; case ApiErrorType.timeout: case ApiErrorType.serverUnavailable: return 'Backend is waking up or temporarily unavailable. Tap refresh after a moment.'; case ApiErrorType.noInternet: return 'No internet connection. Check the network and try again.'; default: return e.message; } } final text=e.toString(); if(text.contains('401')) return 'Session expired. Please login again.'; if(text.contains('403')) return 'Manager/Admin access is required.'; if(text.contains('404')) return 'Manager API is not available on the current backend.'; if(text.contains('SocketException')||text.contains('connection')) return 'Backend is unreachable. Tap refresh after it wakes up.'; return 'Could not load manager controls: $e'; }
  bool get _compatibilityMode => _day?['_managerEndpointUnavailable'] == true;
  void _showBackendUpdate(){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This action needs the Manager API on the server. Deploy the latest backend, then try again.'))); }
  @override Widget build(BuildContext context){ return Scaffold(appBar:AppBar(title:const Text('Manager Center'),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh_rounded))]),body:RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[if(_error!=null)Text(_error!,style:TextStyle(color:AppColors.danger)),if(_loading)const LinearProgressIndicator(),if(_day!=null)...[_hero(),if(_compatibilityMode) ...[const SizedBox(height:10),_compatibilityBanner()],const SizedBox(height:14),_cashCard(),const SizedBox(height:14),_grid(),const SizedBox(height:18),_dailyActions()]]))); }
  Widget _compatibilityBanner(){return Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:AppColors.warning.withValues(alpha:.08),borderRadius:BorderRadius.circular(12),border:Border.all(color:AppColors.warning.withValues(alpha:.25))),child:Row(children:[Icon(Icons.info_outline_rounded,color:AppColors.warning),const SizedBox(width:10),const Expanded(child:Text('Manager controls are available in this app. If a save action returns a server error, deploy the latest backend before retrying.'))]));}
  Widget _hero(){final d=_day!;return Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:AppColors.primaryLight,borderRadius:BorderRadius.circular(20)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Today · ${d['date']}',style:const TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:6),Text(Formatters.currency(d['sales']??0),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900)),Text('${d['orders']??0} bills  •  ${d['pendingKitchen']??0} kitchen pending',style:TextStyle(color:AppColors.textSecondary)),const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[_pill('Cash ${Formatters.currency(d['cashSales']??0)}'),_pill('UPI ${Formatters.currency(d['upi']??0)}'),_pill('Credit ${Formatters.currency(d['credit']??0)}'),_pill('Low stock ${d['lowStock']??0}')]) ]));}
  Widget _pill(String t)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,borderRadius:BorderRadius.circular(10)),child:Text(t,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700)));
  Widget _cashCard(){final d=_day!;return Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,borderRadius:BorderRadius.circular(18),border:Border.all(color:AppColors.border)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[const Icon(Icons.account_balance_wallet_outlined),const SizedBox(width:8),const Text('Cash control',style:TextStyle(fontWeight:FontWeight.w900,fontSize:16)),const Spacer(),Text(d['closed']==true?'CLOSED':'OPEN',style:TextStyle(color:d['closed']==true?AppColors.success:AppColors.warning,fontWeight:FontWeight.w900))]),const SizedBox(height:12),_line('Opening cash',d['openingCash']),_line('Expected cash',d['expectedCash']),_line('Cash expenses',d['cashExpenses']),if(d['shift']?['actualCash']!=null)_line('Actual cash',d['shift']['actualCash']),if(d['shift']?['difference']!=null)_line('Difference',d['shift']['difference'])]));}
  Widget _line(String a,d)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(a)),Text(Formatters.currency(d??0),style:const TextStyle(fontWeight:FontWeight.w800))]));
  Widget _grid(){final items=[('Wastage',Icons.delete_sweep_outlined,_wastage),('Purchases',Icons.local_shipping_outlined,_purchase),('Cash In',Icons.add_card_outlined,()=>_cash('IN')),('Cash Out',Icons.remove_circle_outline,()=>_cash('OUT'))];return GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),mainAxisSpacing:10,crossAxisSpacing:10,childAspectRatio:2.5,children:items.map((x)=>InkWell(onTap:x.$3,borderRadius:BorderRadius.circular(15),child:Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Theme.of(context).colorScheme.surface,borderRadius:BorderRadius.circular(15),border:Border.all(color:AppColors.border)),child:Row(children:[Icon(x.$2,color:AppColors.primary),const SizedBox(width:8),Text(x.$1,style:const TextStyle(fontWeight:FontWeight.w800))])))).toList());}
  Widget _dailyActions()=>Row(children:[Expanded(child:ElevatedButton.icon(onPressed:_day!['shift']==null?()=>_openDay():null,icon:const Icon(Icons.play_arrow_rounded),label:const Text('Open Day'))),const SizedBox(width:10),Expanded(child:OutlinedButton.icon(onPressed:_day!['shift']!=null&&_day!['closed']!=true?()=>_closeDay():null,icon:const Icon(Icons.lock_clock_rounded),label:const Text('Close Day')))]);
  Future<void> _openDay() async {final c=TextEditingController();await showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Open Business Day'),content:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Opening cash (₹)')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()async{await _service.openDay(double.tryParse(c.text)??0);if(mounted)Navigator.pop(context);_load();},child:const Text('Open'))]));}
  Future<void> _closeDay() async {final c=TextEditingController();await showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Close Business Day'),content:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Actual cash counted (₹)')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()async{await _service.closeDay(double.tryParse(c.text)??0);if(mounted)Navigator.pop(context);_load();},child:const Text('Close Day'))]));}
  Future<void> _cash(String type) async {final a=TextEditingController(),r=TextEditingController();await showDialog(context:context,builder:(_)=>AlertDialog(title:Text(type=='IN'?'Add Cash':'Remove Cash'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:a,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount')),TextField(controller:r,decoration:const InputDecoration(labelText:'Reason'))]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()async{await _service.cashMovement(type,double.tryParse(a.text)??0,r.text);if(mounted)Navigator.pop(context);_load();},child:const Text('Save'))]));}
  Future<void> _wastage() async {
    List<Product> ps = [];
    try { ps = await _products.list(status: 'available'); } catch (_) { return; }
    String? id = ps.isNotEmpty ? ps.first.id : null;
    String reason = 'Other';
    final q = TextEditingController();
    final notes = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Record Wastage'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: id,
                items: ps.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                onChanged: (v) => set(() => id = v),
                decoration: const InputDecoration(labelText: 'Item'),
              ),
              TextField(controller: q, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity')),
              DropdownButtonFormField<String>(
                value: reason,
                items: ['Burnt','Expired','Spoilage','Wrong Preparation','Customer Return','Other'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                onChanged: (v) => set(() => reason = v ?? 'Other'),
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (id == null) return;
                await _service.wastage(id!, double.tryParse(q.text) ?? 0, reason, notes.text);
                if (mounted) Navigator.pop(c);
                _load();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _purchase() async {
    List<Product> ps = [];
    try { ps = await _products.list(status: 'available'); } catch (_) { return; }
    String? id = ps.isNotEmpty ? ps.first.id : null;
    final supplier = TextEditingController();
    final qty = TextEditingController();
    final cost = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('New Purchase'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Supplier')),
              DropdownButtonFormField<String>(
                value: id,
                items: ps.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                onChanged: (v) => set(() => id = v),
                decoration: const InputDecoration(labelText: 'Product'),
              ),
              TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity')),
              TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unit cost (₹)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (id == null) return;
                await _service.purchase(supplier: supplier.text, items: [
                  {'productId': id, 'quantity': double.tryParse(qty.text) ?? 0, 'unitCost': double.tryParse(cost.text) ?? 0}
                ]);
                if (mounted) Navigator.pop(c);
                _load();
              },
              child: const Text('Save Purchase'),
            ),
          ],
        ),
      ),
    );
  }

}
