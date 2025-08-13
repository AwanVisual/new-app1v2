import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from '@/components/ui/alert-dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Plus, Edit, Package, Search, Trash2 } from 'lucide-react';
import { PackagePlus, PackageMinus } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { formatCurrency } from '@/lib/utils';
import CategoryInput from '@/components/CategoryInput';
import { useAuth } from '@/hooks/useAuth';

const Products = () => {
  const { userRole, user } = useAuth();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<any>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedProduct, setSelectedProduct] = useState<any>(null);
  const [isStockDialogOpen, setIsStockDialogOpen] = useState(false);
  const [isReduceStockDialogOpen, setIsReduceStockDialogOpen] = useState(false);
  const [stockQuantity, setStockQuantity] = useState<number>(0);
  const [reduceStockQuantity, setReduceStockQuantity] = useState<number>(0);
  const [stockUnitType, setStockUnitType] = useState<'pcs' | 'base_unit'>('base_unit');
  const [reduceStockUnitType, setReduceStockUnitType] = useState<'pcs' | 'base_unit'>('base_unit');
  const [stockNotes, setStockNotes] = useState('');
  const [reduceStockNotes, setReduceStockNotes] = useState('');
  const [selectedProductHistory, setSelectedProductHistory] = useState<any>(null);
  const [isHistoryDialogOpen, setIsHistoryDialogOpen] = useState(false);

  const canManage = userRole === 'admin' || userRole === 'stockist';

  const { data: products, isLoading } = useQuery({
    queryKey: ['products'],
    queryFn: async () => {
      const { data } = await supabase
        .from('products')
        .select('*, categories(name)')
        .order('created_at', { ascending: false });
      return data || [];
    },
  });

  const { data: categories } = useQuery({
    queryKey: ['categories'],
    queryFn: async () => {
      const { data } = await supabase.from('categories').select('*');
      return data || [];
    },
  });

  const { data: stockMovements } = useQuery({
    queryKey: ['stock-movements', selectedProductHistory?.id],
    queryFn: async () => {
      if (!selectedProductHistory?.id) return [];
      const { data } = await supabase
        .from('stock_movements')
        .select('*, profiles(full_name)')
        .eq('product_id', selectedProductHistory.id)
        .order('created_at', { ascending: false });
      return data || [];
    },
    enabled: !!selectedProductHistory?.id,
  });

  const createProductMutation = useMutation({
    mutationFn: async (productData: any) => {
      const { error } = await supabase.from('products').insert([productData]);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['products'] });
      setIsDialogOpen(false);
      toast({ title: "Success", description: "Product created successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const updateProductMutation = useMutation({
    mutationFn: async ({ id, ...productData }: any) => {
      const { error } = await supabase
        .from('products')
        .update(productData)
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['products'] });
      setIsDialogOpen(false);
      setEditingProduct(null);
      toast({ title: "Success", description: "Product updated successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const deleteProductMutation = useMutation({
    mutationFn: async (productId: string) => {
      // First delete all associated sale items
      const { error: saleItemsError } = await supabase
        .from('sale_items')
        .delete()
        .eq('product_id', productId);
      
      if (saleItemsError) throw saleItemsError;
      
      // Then delete the product
      const { error } = await supabase
        .from('products')
        .delete()
        .eq('id', productId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['products'] });
      toast({ title: "Success", description: "Product deleted successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const addStockMutation = useMutation({
    mutationFn: async ({ productId, quantity, unitType, notes }: any) => {
      const { error } = await supabase.from('stock_movements').insert([{
        product_id: productId,
        transaction_type: 'inbound',
        quantity: quantity,
        unit_type: unitType,
        notes: notes || 'Stock addition',
        created_by: user?.id,
        reference_number: `STOCK-${Date.now()}`
      }]);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['products'] });
      setIsStockDialogOpen(false);
      setSelectedProduct(null);
      setStockQuantity(0);
      setStockNotes('');
      toast({ title: "Success", description: "Stock added successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const reduceStockMutation = useMutation({
    mutationFn: async ({ productId, quantity, unitType, notes }: any) => {
      const { error } = await supabase.from('stock_movements').insert([{
        product_id: productId,
        transaction_type: 'outbound',
        quantity: quantity,
        unit_type: unitType,
        notes: notes || 'Stock reduction',
        created_by: user?.id,
        reference_number: `REDUCE-${Date.now()}`
      }]);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['products'] });
      setIsReduceStockDialogOpen(false);
      setSelectedProduct(null);
      setReduceStockQuantity(0);
      setReduceStockNotes('');
      toast({ title: "Success", description: "Stock reduced successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const handleAddStock = () => {
    if (!selectedProduct || stockQuantity <= 0) {
      toast({ title: "Error", description: "Please enter a valid quantity", variant: "destructive" });
      return;
    }

    addStockMutation.mutate({
      productId: selectedProduct.id,
      quantity: stockQuantity,
      unitType: stockUnitType,
      notes: stockNotes
    });
  };

  const handleReduceStock = () => {
    if (!selectedProduct || reduceStockQuantity <= 0) {
      toast({ title: "Error", description: "Please enter a valid quantity", variant: "destructive" });
      return;
    }

    // Check if there's enough stock to reduce
    const availableStock = reduceStockUnitType === 'pcs' 
      ? selectedProduct.stock_pcs || 0
      : selectedProduct.stock_quantity || 0;

    if (reduceStockQuantity > availableStock) {
      toast({ 
        title: "Error", 
        description: `Not enough stock. Available: ${availableStock} ${reduceStockUnitType === 'pcs' ? 'pcs' : selectedProduct.base_unit}`, 
        variant: "destructive" 
      });
      return;
    }

    reduceStockMutation.mutate({
      productId: selectedProduct.id,
      quantity: reduceStockQuantity,
      unitType: reduceStockUnitType,
      notes: reduceStockNotes
    });
  };

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    
    const categoryId = formData.get('category_id') as string;
    const stockQuantity = parseInt(formData.get('stock_quantity') as string);
    const pcsPerBaseUnit = parseInt(formData.get('pcs_per_base_unit') as string);
    const calculatedStockPcs = stockQuantity * pcsPerBaseUnit;
    
    const productData = {
      name: formData.get('name') as string,
      sku: formData.get('sku') as string,
      category_id: categoryId === 'no-category' ? null : categoryId,
      price: parseFloat(formData.get('price') as string),
      price_per_pcs: parseFloat(formData.get('price_per_pcs') as string),
      cost: parseFloat(formData.get('price_per_pcs') as string), // Use price_per_pcs as cost for now
      stock_quantity: stockQuantity,
      stock_pcs: parseInt(formData.get('stock_pcs') as string),
      min_stock_level: parseInt(formData.get('min_stock_level') as string),
      description: formData.get('description') as string,
      base_unit: formData.get('base_unit') as string,
      pcs_per_base_unit: pcsPerBaseUnit,
      // Add initial stock tracking for new products
      ...(editingProduct ? {} : {
        initial_stock_quantity: stockQuantity,
        initial_stock_pcs: parseInt(formData.get('stock_pcs') as string),
        total_stock_added: 0,
        total_stock_reduced: 0,
        stock_movement_count: 0,
      }),
    };

    if (editingProduct) {
      updateProductMutation.mutate({ id: editingProduct.id, ...productData });
    } else {
      createProductMutation.mutate(productData);
    }
  };

  const filteredProducts = products?.filter(product =>
    product.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    product.sku.toLowerCase().includes(searchTerm.toLowerCase())
  );

  // Close units manager when dialog closes
  const handleDialogClose = (open: boolean) => {
    setIsDialogOpen(open);
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold text-gray-900">Products</h1>
        <div className="flex gap-2">
          {canManage && <CategoryInput />}
          {canManage && (
            <Dialog open={isDialogOpen} onOpenChange={handleDialogClose}>
              <DialogTrigger asChild>
                <Button onClick={() => setEditingProduct(null)}>
                  <Plus className="h-4 w-4 mr-2" />
                  Add Product
                </Button>
              </DialogTrigger>
              <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
                <DialogHeader>
                  <DialogTitle>
                    {editingProduct ? 'Edit Product' : 'Add New Product'}
                  </DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <Label htmlFor="name">Product Name</Label>
                      <Input
                        id="name"
                        name="name"
                        defaultValue={editingProduct?.name}
                        required
                      />
                    </div>
                    <div>
                      <Label htmlFor="sku">SKU</Label>
                      <Input
                        id="sku"
                        name="sku"
                        defaultValue={editingProduct?.sku}
                        required
                      />
                    </div>
                  </div>
                  
                  <div>
                    <Label htmlFor="category_id">Category</Label>
                    <Select name="category_id" defaultValue={editingProduct?.category_id || "no-category"}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select category" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="no-category">No Category</SelectItem>
                        {categories?.map((category) => (
                          <SelectItem key={category.id} value={category.id}>
                            {category.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <Label htmlFor="price">Price per Base Unit</Label>
                      <Input
                        id="price"
                        name="price"
                        type="number"
                        step="0.01"
                        defaultValue={editingProduct?.price}
                        required
                      />
                      <p className="text-sm text-muted-foreground mt-1">
                        Price per {editingProduct?.base_unit || 'base unit'}
                      </p>
                    </div>
                    <div>
                      <Label htmlFor="price_per_pcs">Price per Piece</Label>
                      <Input
                        id="price_per_pcs"
                        name="price_per_pcs"
                        type="number"
                        step="0.01"
                        defaultValue={editingProduct?.price_per_pcs}
                        required
                      />
                      <p className="text-sm text-muted-foreground mt-1">
                        Price per pcs
                      </p>
                    </div>
                  </div>

                  <div>
                    <Label htmlFor="base_unit">Base Unit</Label>
                    <Select name="base_unit" defaultValue={editingProduct?.base_unit || "pcs"}>
                      <SelectTrigger>
                        <SelectValue placeholder="Select base unit" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="pcs">Pieces (pcs)</SelectItem>
                        <SelectItem value="dus">Dus/Box</SelectItem>
                        <SelectItem value="lusin">Lusin (12 pcs)</SelectItem>
                        <SelectItem value="kodi">Kodi (20 pcs)</SelectItem>
                        <SelectItem value="gross">Gross (144 pcs)</SelectItem>
                        <SelectItem value="kg">Kilogram</SelectItem>
                        <SelectItem value="gram">Gram</SelectItem>
                        <SelectItem value="liter">Liter</SelectItem>
                        <SelectItem value="ml">Mililiter</SelectItem>
                        <SelectItem value="meter">Meter</SelectItem>
                        <SelectItem value="cm">Centimeter</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  <div>
                    <Label htmlFor="pcs_per_base_unit">Conversion to Pieces</Label>
                    <div className="flex items-center space-x-2">
                      <span className="text-sm">1 {editingProduct?.base_unit || 'base unit'} =</span>
                      <Input
                        id="pcs_per_base_unit"
                        name="pcs_per_base_unit"
                        type="number"
                        min="1"
                        defaultValue={editingProduct?.pcs_per_base_unit || 1}
                        onChange={(e) => {
                          const pcsPerUnit = Number(e.target.value) || 1;
                          const stockQty = Number((document.getElementById('stock_quantity') as HTMLInputElement)?.value) || 0;
                          const stockPcsInput = document.getElementById('stock_pcs') as HTMLInputElement;
                          if (stockPcsInput) {
                            stockPcsInput.value = (stockQty * pcsPerUnit).toString();
                          }
                        }}
                        required
                        className="w-20"
                      />
                      <span className="text-sm">pcs</span>
                    </div>
                    <p className="text-sm text-muted-foreground mt-1">
                      How many pieces equal 1 base unit?
                    </p>
                  </div>

                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <Label htmlFor="stock_quantity">Stock Quantity (Base Unit)</Label>
                      <Input
                        id="stock_quantity"
                        name="stock_quantity"
                        type="number"
                        defaultValue={editingProduct?.stock_quantity || 0}
                        onChange={(e) => {
                          const stockQty = Number(e.target.value) || 0;
                          const pcsPerUnit = Number((document.getElementById('pcs_per_base_unit') as HTMLInputElement)?.value) || 1;
                          const stockPcsInput = document.getElementById('stock_pcs') as HTMLInputElement;
                          if (stockPcsInput) {
                            stockPcsInput.value = (stockQty * pcsPerUnit).toString();
                          }
                          // Update initial stock fields for new products
                          if (!editingProduct) {
                            const initialStockQtyInput = document.getElementById('initial_stock_quantity') as HTMLInputElement;
                            const initialStockPcsInput = document.getElementById('initial_stock_pcs') as HTMLInputElement;
                            if (initialStockQtyInput) initialStockQtyInput.value = stockQty.toString();
                            if (initialStockPcsInput) initialStockPcsInput.value = (stockQty * pcsPerUnit).toString();
                          }
                        }}
                        required
                      />
                      <p className="text-sm text-muted-foreground mt-1">
                        Stock in {editingProduct?.base_unit || 'base units'}
                      </p>
                    </div>
                    <div>
                      <Label htmlFor="stock_pcs">Stock in Pieces</Label>
                      <Input
                        id="stock_pcs"
                        name="stock_pcs"
                        type="number"
                        defaultValue={editingProduct?.stock_pcs || 0}
                        onChange={(e) => {
                          const stockPcs = Number(e.target.value) || 0;
                          const pcsPerUnit = Number((document.getElementById('pcs_per_base_unit') as HTMLInputElement)?.value) || 1;
                          const stockQtyInput = document.getElementById('stock_quantity') as HTMLInputElement;
                          if (stockQtyInput && pcsPerUnit > 0) {
                            const calculatedBaseUnits = Math.floor(stockPcs / pcsPerUnit);
                            stockQtyInput.value = calculatedBaseUnits.toString();
                          }
                          // Update initial stock fields for new products
                          if (!editingProduct) {
                            const initialStockQtyInput = document.getElementById('initial_stock_quantity') as HTMLInputElement;
                            const initialStockPcsInput = document.getElementById('initial_stock_pcs') as HTMLInputElement;
                            if (initialStockPcsInput) initialStockPcsInput.value = stockPcs.toString();
                            if (initialStockQtyInput && pcsPerUnit > 0) {
                              initialStockQtyInput.value = Math.floor(stockPcs / pcsPerUnit).toString();
                            }
                          }
                        }}
                        required
                      />
                      <p className="text-sm text-muted-foreground mt-1">
                        Stock in pieces (editable)
                      </p>
                    </div>
                  </div>

                  {/* Initial Stock Fields (hidden inputs for new products) */}
                  <input type="hidden" id="initial_stock_quantity" name="initial_stock_quantity" defaultValue={editingProduct?.initial_stock_quantity || 0} />
                  <input type="hidden" id="initial_stock_pcs" name="initial_stock_pcs" defaultValue={editingProduct?.initial_stock_pcs || 0} />

                  <div>
                    <Label htmlFor="min_stock_level">Min Stock Level (Pieces)</Label>
                    <Input
                      id="min_stock_level"
                      name="min_stock_level"
                      type="number"
                      defaultValue={editingProduct?.min_stock_level || 10}
                      required
                    />
                    <p className="text-sm text-muted-foreground mt-1">
                      Minimum stock in pieces
                    </p>
                  </div>

                  <div>
                    <Label htmlFor="description">Description</Label>
                    <Textarea
                      id="description"
                      name="description"
                      defaultValue={editingProduct?.description}
                    />
                  </div>

                  <div className="flex justify-end space-x-2">
                    <Button type="button" variant="outline" onClick={() => handleDialogClose(false)}>
                      Cancel
                    </Button>
                    <Button type="submit">
                      {editingProduct ? 'Update' : 'Create'} Product
                    </Button>
                  </div>
                </form>
              </DialogContent>
            </Dialog>
          )}
        </div>
      </div>

      <Card>
        <CardHeader>
          <div className="flex items-center space-x-2">
            <Search className="h-4 w-4" />
            <Input
              placeholder="Search products..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="max-w-sm"
            />
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Product</TableHead>
                <TableHead>SKU</TableHead>
                <TableHead>Category</TableHead>
                <TableHead>Base Unit</TableHead>
                <TableHead>Price</TableHead>
                <TableHead>Stock</TableHead>
               <TableHead>History</TableHead>
                <TableHead>Status</TableHead>
                {canManage && <TableHead>Actions</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredProducts?.map((product) => (
                <TableRow key={product.id}>
                  <TableCell>
                    <div>
                      <div className="font-medium">{product.name}</div>
                      <div className="text-sm text-muted-foreground">
                        {product.description}
                      </div>
                    </div>
                  </TableCell>
                  <TableCell>{product.sku}</TableCell>
                  <TableCell>{product.categories?.name || 'No Category'}</TableCell>
                  <TableCell>{product.base_unit || 'pcs'}</TableCell>
                  <TableCell>{formatCurrency(Number(product.price))}</TableCell>
                  <TableCell>
                    <div className="flex items-center space-x-2">
                      <Package className="h-4 w-4" />
                      <span>{product.stock_quantity} {product.base_unit || 'pcs'}</span>
                      {product.base_unit !== 'pcs' && (product.pcs_per_base_unit || 1) > 1 && (
                        <span className="text-xs text-muted-foreground">
                          ({product.stock_pcs || 0} pcs)
                        </span>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => {
                        setSelectedProductHistory(product);
                        setIsHistoryDialogOpen(true);
                      }}
                      className="text-blue-600 hover:text-blue-700 hover:bg-blue-50"
                    >
                      <Package className="h-4 w-4 mr-1" />
                      {product.stock_movement_count || 0}x
                    </Button>
                  </TableCell>
                  <TableCell>
                    <Badge
                      variant={
                        (product.stock_pcs || 0) <= (product.min_stock_level || 10)
                          ? "destructive"
                          : "default"
                      }
                    >
                      {(product.stock_pcs || 0) <= (product.min_stock_level || 10)
                        ? "Low Stock"
                        : "In Stock"
                      }
                    </Badge>
                  </TableCell>
                  {canManage && (
                    <TableCell>
                      <div className="flex items-center space-x-2">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => {
                            setEditingProduct(product);
                            setIsDialogOpen(true);
                          }}
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => {
                            setSelectedProduct(product);
                            setIsStockDialogOpen(true);
                          }}
                          className="text-green-600 hover:text-green-700 hover:bg-green-50"
                        >
                          <PackagePlus className="h-4 w-4" />
                        </Button>
                        
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => {
                            setSelectedProduct(product);
                            setIsReduceStockDialogOpen(true);
                          }}
                          className="text-orange-600 hover:text-orange-700 hover:bg-orange-50"
                        >
                          <PackageMinus className="h-4 w-4" />
                        </Button>
                        
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button
                              variant="outline"
                              size="sm"
                              className="text-red-600 hover:text-red-700 hover:bg-red-50"
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Delete Product</AlertDialogTitle>
                              <AlertDialogDescription>
                                Are you sure you want to delete "{product.name}"? 
                                This action cannot be undone and will permanently remove the product 
                                and all associated data including stock movements and sale items.
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancel</AlertDialogCancel>
                              <AlertDialogAction
                                onClick={() => deleteProductMutation.mutate(product.id)}
                                className="bg-red-600 hover:bg-red-700"
                                disabled={deleteProductMutation.isPending}
                              >
                                {deleteProductMutation.isPending ? 'Deleting...' : 'Delete Product'}
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Add Stock Dialog */}
      <Dialog open={isStockDialogOpen} onOpenChange={setIsStockDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add Stock - {selectedProduct?.name}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="stockUnitType">Unit Type</Label>
              <Select value={stockUnitType} onValueChange={(value: 'pcs' | 'base_unit') => setStockUnitType(value)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="base_unit">{selectedProduct?.base_unit || 'Base Unit'}</SelectItem>
                  <SelectItem value="pcs">Pieces (pcs)</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-sm text-muted-foreground mt-1">
                {stockUnitType === 'base_unit' 
                  ? `1 ${selectedProduct?.base_unit} = ${selectedProduct?.pcs_per_base_unit || 1} pcs`
                  : 'Direct piece count'
                }
              </p>
            </div>

            <div>
              <Label htmlFor="stockQuantity">Quantity to Add</Label>
              <Input
                id="stockQuantity"
                type="number"
                min="1"
                value={stockQuantity}
                onChange={(e) => setStockQuantity(parseInt(e.target.value) || 0)}
                placeholder="Enter quantity"
              />
              {stockUnitType === 'base_unit' && selectedProduct?.pcs_per_base_unit > 1 && (
                <p className="text-sm text-muted-foreground mt-1">
                  This will add {stockQuantity * (selectedProduct?.pcs_per_base_unit || 1)} pieces to stock
                </p>
              )}
            </div>

            <div>
              <Label htmlFor="stockNotes">Notes (Optional)</Label>
              <Input
                id="stockNotes"
                value={stockNotes}
                onChange={(e) => setStockNotes(e.target.value)}
                placeholder="Add notes for this stock movement"
              />
            </div>

            <div className="flex justify-end space-x-2">
              <Button 
                type="button" 
                variant="outline" 
                onClick={() => setIsStockDialogOpen(false)}
              >
                Cancel
              </Button>
              <Button 
                onClick={handleAddStock}
                disabled={addStockMutation.isPending || stockQuantity <= 0}
              >
                {addStockMutation.isPending ? 'Adding...' : 'Add Stock'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Reduce Stock Dialog */}
      <Dialog open={isReduceStockDialogOpen} onOpenChange={setIsReduceStockDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reduce Stock - {selectedProduct?.name}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="reduceStockUnitType">Unit Type</Label>
              <Select value={reduceStockUnitType} onValueChange={(value: 'pcs' | 'base_unit') => setReduceStockUnitType(value)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="base_unit">{selectedProduct?.base_unit || 'Base Unit'}</SelectItem>
                  <SelectItem value="pcs">Pieces (pcs)</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-sm text-muted-foreground mt-1">
                {reduceStockUnitType === 'base_unit' 
                  ? `1 ${selectedProduct?.base_unit} = ${selectedProduct?.pcs_per_base_unit || 1} pcs`
                  : 'Direct piece count'
                }
              </p>
              <p className="text-sm text-blue-600 mt-1">
                Available: {reduceStockUnitType === 'pcs' 
                  ? `${selectedProduct?.stock_pcs || 0} pcs`
                  : `${selectedProduct?.stock_quantity || 0} ${selectedProduct?.base_unit || 'units'}`
                }
              </p>
            </div>

            <div>
              <Label htmlFor="reduceStockQuantity">Quantity to Reduce</Label>
              <Input
                id="reduceStockQuantity"
                type="number"
                min="1"
                max={reduceStockUnitType === 'pcs' 
                  ? selectedProduct?.stock_pcs || 0
                  : selectedProduct?.stock_quantity || 0
                }
                value={reduceStockQuantity}
                onChange={(e) => setReduceStockQuantity(parseInt(e.target.value) || 0)}
                placeholder="Enter quantity to reduce"
              />
              {reduceStockUnitType === 'base_unit' && selectedProduct?.pcs_per_base_unit > 1 && (
                <p className="text-sm text-muted-foreground mt-1">
                  This will reduce {reduceStockQuantity * (selectedProduct?.pcs_per_base_unit || 1)} pieces from stock
                </p>
              )}
            </div>

            <div>
              <Label htmlFor="reduceStockNotes">Reason (Optional)</Label>
              <Input
                id="reduceStockNotes"
                value={reduceStockNotes}
                onChange={(e) => setReduceStockNotes(e.target.value)}
                placeholder="Reason for stock reduction (e.g., damaged, expired, etc.)"
              />
            </div>

            <div className="flex justify-end space-x-2">
              <Button 
                type="button" 
                variant="outline" 
                onClick={() => setIsReduceStockDialogOpen(false)}
              >
                Cancel
              </Button>
              <Button 
                onClick={handleReduceStock}
                disabled={reduceStockMutation.isPending || reduceStockQuantity <= 0}
                className="bg-orange-600 hover:bg-orange-700"
              >
                {reduceStockMutation.isPending ? 'Reducing...' : 'Reduce Stock'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Stock History Dialog */}
      <Dialog open={isHistoryDialogOpen} onOpenChange={setIsHistoryDialogOpen}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Stock History - {selectedProductHistory?.name}</DialogTitle>
          </DialogHeader>
          
          {selectedProductHistory && (
            <div className="space-y-6">
              {/* Initial Stock Info */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Initial Stock Information</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                    <div className="text-center">
                      <div className="text-2xl font-bold text-blue-600">
                        {selectedProductHistory.initial_stock_quantity || 0}
                      </div>
                      <div className="text-sm text-muted-foreground">
                        Initial {selectedProductHistory.base_unit || 'units'}
                      </div>
                    </div>
                    <div className="text-center">
                      <div className="text-2xl font-bold text-blue-600">
                        {selectedProductHistory.initial_stock_pcs || 0}
                      </div>
                      <div className="text-sm text-muted-foreground">Initial Pieces</div>
                    </div>
                    <div className="text-center">
                      <div className="text-2xl font-bold text-green-600">
                        +{selectedProductHistory.total_stock_added || 0}
                      </div>
                      <div className="text-sm text-muted-foreground">Total Added (pcs)</div>
                    </div>
                    <div className="text-center">
                      <div className="text-2xl font-bold text-red-600">
                        -{selectedProductHistory.total_stock_reduced || 0}
                      </div>
                      <div className="text-sm text-muted-foreground">Total Reduced (pcs)</div>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* Current Stock Status */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Current Stock Status</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 gap-4">
                    <div className="text-center">
                      <div className="text-3xl font-bold text-purple-600">
                        {selectedProductHistory.stock_quantity || 0}
                      </div>
                      <div className="text-sm text-muted-foreground">
                        Current {selectedProductHistory.base_unit || 'units'}
                      </div>
                    </div>
                    <div className="text-center">
                      <div className="text-3xl font-bold text-purple-600">
                        {selectedProductHistory.stock_pcs || 0}
                      </div>
                      <div className="text-sm text-muted-foreground">Current Pieces</div>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* Stock Movement History */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Stock Movement History</CardTitle>
                </CardHeader>
                <CardContent>
                  {stockMovements && stockMovements.length > 0 ? (
                    <div className="space-y-3 max-h-96 overflow-y-auto">
                      {stockMovements.map((movement) => (
                        <div 
                          key={movement.id} 
                          className={`border rounded-lg p-4 ${
                            movement.transaction_type === 'inbound' 
                              ? 'border-green-200 bg-green-50' 
                              : movement.transaction_type === 'outbound'
                              ? 'border-red-200 bg-red-50'
                              : 'border-yellow-200 bg-yellow-50'
                          }`}
                        >
                          <div className="flex items-center justify-between mb-2">
                            <div className="flex items-center space-x-2">
                              <Badge 
                                variant={
                                  movement.transaction_type === 'inbound' 
                                    ? 'default' 
                                    : movement.transaction_type === 'outbound'
                                    ? 'destructive'
                                    : 'secondary'
                                }
                              >
                                {movement.transaction_type === 'inbound' ? 'Stock In' : 
                                 movement.transaction_type === 'outbound' ? 'Stock Out' : 'Adjustment'}
                              </Badge>
                              <span className="text-sm text-muted-foreground">
                                {new Date(movement.created_at).toLocaleDateString('id-ID', {
                                  year: 'numeric',
                                  month: 'short',
                                  day: 'numeric',
                                  hour: '2-digit',
                                  minute: '2-digit'
                                })}
                              </span>
                            </div>
                            <div className="text-right">
                              <div className={`text-lg font-bold ${
                                movement.transaction_type === 'inbound' ? 'text-green-600' : 'text-red-600'
                              }`}>
                                {movement.transaction_type === 'inbound' ? '+' : '-'}
                                {movement.quantity} {movement.unit_type === 'pcs' ? 'pcs' : selectedProductHistory.base_unit}
                              </div>
                              {movement.unit_type === 'base_unit' && selectedProductHistory.pcs_per_base_unit > 1 && (
                                <div className="text-sm text-muted-foreground">
                                  ({movement.transaction_type === 'inbound' ? '+' : '-'}
                                  {movement.quantity * (selectedProductHistory.pcs_per_base_unit || 1)} pcs)
                                </div>
                              )}
                            </div>
                          </div>
                          
                          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                            <div>
                              <span className="text-muted-foreground">Reference:</span>
                              <div className="font-medium">{movement.reference_number || 'N/A'}</div>
                            </div>
                            <div>
                              <span className="text-muted-foreground">By:</span>
                              <div className="font-medium">{movement.profiles?.full_name || 'System'}</div>
                            </div>
                          </div>
                          
                          {movement.notes && (
                            <div className="mt-2">
                              <span className="text-muted-foreground text-sm">Notes:</span>
                              <div className="text-sm">{movement.notes}</div>
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="text-center py-8 text-muted-foreground">
                      <Package className="h-12 w-12 mx-auto mb-4 opacity-50" />
                      <p>No stock movements recorded yet</p>
                    </div>
                  )}
                </CardContent>
              </Card>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Products;