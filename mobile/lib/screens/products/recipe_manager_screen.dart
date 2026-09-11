import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/product.dart';
import '../../services/catalog_service.dart';

class RecipeManagerScreen extends StatefulWidget{const RecipeManagerScreen({super.key});@override State<RecipeManagerScreen> createState()=>_RecipeManagerScreenState();}
class _RecipeManagerScreenState extends State<RecipeManagerScreen>{final svc=ProductService();List<Product> products=[];Product? selected;List<Map<String,dynamic>> lines=[];bool loading=true;String? error;
@override void initState(){super.initState();load();}Future<void> load()async{try{products=await svc.list(status:'available');if(selected!=null)selected=products.firstWhere((p)=>p.id==selected!.id,orElse:()=>products.first);if(selected!=null)lines=selected!.recipe.map((r)=>Map<String,dynamic>.from(r)).toList();}catch(_){error='Could not load products.';}finally{if(mounted)setState(()=>loading=false);}}
void choose(Product? p){setState((){selected=p;lines=p?.recipe.map((r)=>Map<String,dynamic>.from(r)).toList()??[];});}
Future<void> addLine()async{if(selected==null||products.length<2)return;String? id=products.firstWhere((p)=>p.id!=selected!.id,orElse:()=>products.first).id;double qty=1;await showDialog(context:context,builder:(_)=>StatefulBuilder(builder:(c,set)=>AlertDialog(title:const Text('Add ingredient'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField<String>(value:id,items:products.where((p)=>p.id!=selected!.id).map((p)=>DropdownMenuItem(value:p.id,child:Text(p.name))).toList(),onChanged:(v)=>set(()=>id=v),decoration:const InputDecoration(labelText:'Ingredient')),TextField(decoration:const InputDecoration(labelText:'Quantity per 1 sale'),keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(v)=>qty=double.tryParse(v)??1)]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:(){lines.removeWhere((x)=>x['ingredient']==id);lines.add({'ingredient':id,'quantity':qty,'unit':'unit'});Navigator.pop(c);setState((){});},child:const Text('Add'))])));}
Future<void> save()async{if(selected==null)return;try{await svc.update(selected!.id,{'recipe':lines});await load();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Recipe saved. Sales will consume ingredients automatically.')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not save recipe.')));}}
String name(String? id){for(final p in products){if(p.id==id)return p.name;}return 'Ingredient';}
@override
Widget build(BuildContext c) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Recipes / Food Cost'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded))],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null) Text(error!, style: TextStyle(color: AppColors.danger)),
              DropdownButtonFormField<String>(
                value: selected?.id,
                items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  choose(products.firstWhere((p) => p.id == v));
                },
                decoration: const InputDecoration(labelText: 'Menu item / finished product'),
              ),
              const SizedBox(height: 14),
              if (selected != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(15)),
                  child: Text('1 × ${selected!.name} consumes:', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 10),
                ...lines.asMap().entries.map((e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name(e.value['ingredient']?.toString()), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${e.value['quantity']} ${e.value['unit'] ?? 'unit'}'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => lines.removeAt(e.key))),
                )),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: addLine, icon: const Icon(Icons.add), label: const Text('Add ingredient')),
                const SizedBox(height: 10),
                FilledButton.icon(onPressed: save, icon: const Icon(Icons.save_outlined), label: const Text('Save Recipe')),
              ],
              const SizedBox(height: 24),
              Text('Tip: recipe stock is deducted from ingredients when the menu item is sold. Set ingredient stock through Purchases.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
  );
}
}
