import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Checkbox } from '@/components/ui/checkbox';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { useToast } from '@/hooks/use-toast';
import { formatCurrency } from '@/lib/utils';
import { Minus, Plus, Trash2, ShoppingCart, Search, RotateCcw, Loader2, AlertTriangle } from 'lucide-react';
import PreCheckoutDialog from '@/components/PreCheckoutDialog';
import MidtransPayment from '@/components/MidtransPayment';

interface CartItem {
  product: any;
  quantity: number;
  customDiscount: number;
}

interface ReceiptFieldsConfig {
  showAmount: boolean;
  showDppFaktur: boolean;
  showDiscount: boolean;
  showPpn11: boolean;
  discountPercentage: number;
  useSpecialCustomerCalculation: boolean;
}

const Cashier = () => {
  const { user } = useAuth();
  const { toast } = useToast();
  const queryClient = useQueryClient();

  // Cart state
  const [cart, setCart] = useState<CartItem[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [customerName, setCustomerName] = useState('');
  const [paymentMethod, setPaymentMethod] = useState<'cash' | 'card' | 'transfer' | 'credit'>('cash');
  const [paymentReceived, setPaymentReceived] = useState<number>(0);
  const [isPreCheckoutOpen, setIsPreCheckoutOpen] = useState(false);
  const [isMidtransOpen, setIsMidtransOpen] = useState(false);
  const [receiptConfig, setReceiptConfig] = useState<ReceiptFieldsConfig>({
    showAmount: true,
    showDppFaktur: false,
    showDiscount: false,
    showPpn11: false,
    discountPercentage: 0,
    useSpecialCustomerCalculation: false,
  });

  // Reorder states
  const [isReorderDialogOpen, setIsReorderDialogOpen] = useState(false);
  const [isConfirmReorderOpen, setIsConfirmReorderOpen] = useState(false);
  const [searchSaleNumber, setSearchSaleNumber] = useState('');
  const [foundSale, setFoundSale] = useState<any>(null);
  const [useOriginalNumber, setUseOriginalNumber] = useState(false);
  const [stockConfirmationChecked, setStockConfirmationChecked] = useState(false);

  // Fetch products
  const { data: products, isLoading: productsLoading } = useQuery({
    queryKey: ['products'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('products')
        .select('*, categories(name)')
        .eq('is_active', true)
        .order('name');
      
      if (error) throw error;
      return data || [];
    },
  });

  // Fetch categories
  const { data: categories } = useQuery({
    queryKey: ['categories'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('categories')
        .select('*')
        .order('name');
      
      if (error) throw error;
      return data || [];
    },
  });

  // Search sale mutation
  const searchSaleMutation = useMutation({
    mutationFn: async (saleNumber: string) => {
      const { data, error } = await supabase
        .from('sales')
        .select(`
          *,
          sale_items (
            *,
            products (*)
          )
        `)
        .eq('sale_number', saleNumber)
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      setFoundSale(data);
      setIsReorderDialogOpen(false);
      setIsConfirmReorderOpen(true);
      toast({
        title: "Transaksi Ditemukan",
        description: `Transaksi ${data.sale_number} berhasil ditemukan`,
      });
    },
    onError: () => {
      toast({
        title: "Transaksi Tidak Ditemukan",
        description: "Nomor penjualan tidak ditemukan dalam database",
        variant: "destructive",
      });
    },
  });

  // Create sale mutation
  const createSaleMutation = useMutation({
    mutationFn: async (saleData: any) => {
      const { data: sale, error: saleError } = await supabase
        .from('sales')
        .insert([saleData])
        .select()
        .single();

      if (saleError) throw saleError;

      const saleItems = cart.map(item => ({
        sale_id: sale.id,
        product_id: item.product.id,
        quantity: item.quantity,
        unit_price: Number(item.product.price),
        subtotal: item.quantity * Number(item.product.price) * (1 - item.customDiscount / 100),
        discount: item.customDiscount,
      }));

      const { error: itemsError } = await supabase
        .from('sale_items')
        .insert(saleItems);

      if (itemsError) throw itemsError;

      return sale;
    },
    onSuccess: (sale) => {
      queryClient.invalidateQueries({ queryKey: ['sales'] });
      queryClient.invalidateQueries({ queryKey: ['products'] });
      
      setCart([]);
      setCustomerName('');
      setPaymentReceived(0);
      setReceiptConfig({
        showAmount: true,
        showDppFaktur: false,
        showDiscount: false,
        showPpn11: false,
        discountPercentage: 0,
        useSpecialCustomerCalculation: false,
      });

      toast({
        title: "Transaksi Berhasil",
        description: `Penjualan ${sale.sale_number} berhasil disimpan`,
      });
    },
    onError: (error: any) => {
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  // Handle search sale
  const handleSearchSale = () => {
    if (!searchSaleNumber.trim()) {
      toast({
        title: "Input Kosong",
        description: "Masukkan nomor penjualan terlebih dahulu",
        variant: "destructive",
      });
      return;
    }
    searchSaleMutation.mutate(searchSaleNumber.trim());
  };

  // Handle confirm reorder
  const handleConfirmReorder = () => {
    if (!stockConfirmationChecked) {
      toast({
        title: "Konfirmasi Diperlukan",
        description: "Harap centang konfirmasi penyesuaian stok terlebih dahulu",
        variant: "destructive",
      });
      return;
    }

    if (!foundSale || !foundSale.sale_items) {
      toast({
        title: "Error",
        description: "Data transaksi tidak valid",
        variant: "destructive",
      });
      return;
    }

    // Clear current cart
    setCart([]);

    // Add items from found sale to cart
    const newCart: CartItem[] = foundSale.sale_items.map((item: any) => ({
      product: item.products,
      quantity: item.quantity,
      customDiscount: item.discount || 0,
    }));

    setCart(newCart);
    setCustomerName(foundSale.customer_name || '');

    // Close dialogs and reset states
    setIsConfirmReorderOpen(false);
    setFoundSale(null);
    setSearchSaleNumber('');
    setUseOriginalNumber(false);
    setStockConfirmationChecked(false);

    toast({
      title: "Transaksi Ulang Berhasil",
      description: "Item telah ditambahkan ke keranjang. Silakan lanjutkan transaksi.",
    });
  };

  // Filter products
  const filteredProducts = products?.filter(product => {
    const matchesSearch = product.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         product.sku.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesCategory = selectedCategory === 'all' || product.category_id === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  // Add to cart
  const addToCart = (product: any) => {
    setCart(prev => {
      const existingItem = prev.find(item => item.product.id === product.id);
      if (existingItem) {
        return prev.map(item =>
          item.product.id === product.id
            ? { ...item, quantity: item.quantity + 1 }
            : item
        );
      }
      return [...prev, { product, quantity: 1, customDiscount: 0 }];
    });
  };

  // Update cart quantity
  const updateCartQuantity = (productId: string, quantity: number) => {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }
    setCart(prev =>
      prev.map(item =>
        item.product.id === productId ? { ...item, quantity } : item
      )
    );
  };

  // Remove from cart
  const removeFromCart = (productId: string) => {
    setCart(prev => prev.filter(item => item.product.id !== productId));
  };

  // Calculate totals
  const calculateTotals = () => {
    return cart.reduce((totals, item) => {
      const price = Number(item.product.price);
      const quantity = item.quantity;
      const discountAmount = (item.customDiscount / 100) * price;
      const discountedPrice = price - discountAmount;
      const itemTotal = discountedPrice * quantity;
      
      return {
        subtotal: totals.subtotal + (price * quantity),
        discount: totals.discount + (discountAmount * quantity),
        total: totals.total + itemTotal,
      };
    }, { subtotal: 0, discount: 0, total: 0 });
  };

  const totals = calculateTotals();
  const change = paymentReceived - totals.total;

  // Handle checkout
  const handleCheckout = () => {
    if (cart.length === 0) {
      toast({
        title: "Keranjang Kosong",
        description: "Tambahkan produk ke keranjang terlebih dahulu",
        variant: "destructive",
      });
      return;
    }

    if (paymentMethod === 'transfer') {
      setIsMidtransOpen(true);
    } else {
      setIsPreCheckoutOpen(true);
    }
  };

  // Handle proceed to payment
  const handleProceedToPayment = (config: ReceiptFieldsConfig) => {
    setReceiptConfig(config);
    setIsPreCheckoutOpen(false);

    if (paymentMethod === 'cash' && paymentReceived < totals.total) {
      toast({
        title: "Pembayaran Kurang",
        description: "Jumlah pembayaran kurang dari total belanja",
        variant: "destructive",
      });
      return;
    }

    const saleData = {
      sale_number: useOriginalNumber && foundSale ? foundSale.sale_number : undefined,
      customer_name: customerName || null,
      subtotal: totals.subtotal,
      tax_amount: 0,
      total_amount: totals.total,
      payment_method: paymentMethod,
      payment_received: paymentReceived,
      change_amount: change > 0 ? change : 0,
      created_by: user?.id,
      cashier_id: user?.id,
    };

    createSaleMutation.mutate(saleData);
  };

  // Handle Midtrans payment
  const handleMidtransSuccess = (paymentData: any) => {
    const saleData = {
      customer_name: customerName || null,
      subtotal: totals.subtotal,
      tax_amount: 0,
      total_amount: totals.total,
      payment_method: 'transfer' as const,
      payment_received: totals.total,
      change_amount: 0,
      notes: `Midtrans Payment: ${paymentData.transaction_id}`,
      created_by: user?.id,
      cashier_id: user?.id,
    };

    createSaleMutation.mutate(saleData);
    setIsMidtransOpen(false);
  };

  const handleMidtransError = (error: any) => {
    console.error('Midtrans payment error:', error);
    setIsMidtransOpen(false);
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div className="flex items-center gap-2">
          <ShoppingCart className="h-8 w-8" />
          <div>
            <h1 className="text-3xl font-bold text-gray-900">Cashier</h1>
            <p className="text-gray-600">Point of Sale System</p>
          </div>
        </div>
        <Button
          onClick={() => setIsReorderDialogOpen(true)}
          variant="outline"
          className="flex items-center gap-2"
        >
          <RotateCcw className="h-4 w-4" />
          Transaksi Ulang
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Products Section */}
        <div className="lg:col-span-2 space-y-4">
          {/* Search and Filter */}
          <Card>
            <CardContent className="p-4">
              <div className="flex gap-4">
                <div className="flex-1">
                  <Input
                    placeholder="Cari produk..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="w-full"
                  />
                </div>
                <Select value={selectedCategory} onValueChange={setSelectedCategory}>
                  <SelectTrigger className="w-48">
                    <SelectValue placeholder="Pilih kategori" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">Semua Kategori</SelectItem>
                    {categories?.map((category) => (
                      <SelectItem key={category.id} value={category.id}>
                        {category.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </CardContent>
          </Card>

          {/* Products Grid */}
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
            {productsLoading ? (
              Array.from({ length: 8 }).map((_, i) => (
                <Card key={i} className="animate-pulse">
                  <CardContent className="p-4">
                    <div className="h-4 bg-gray-200 rounded mb-2"></div>
                    <div className="h-4 bg-gray-200 rounded mb-2"></div>
                    <div className="h-8 bg-gray-200 rounded"></div>
                  </CardContent>
                </Card>
              ))
            ) : (
              filteredProducts?.map((product) => (
                <Card key={product.id} className="cursor-pointer hover:shadow-md transition-shadow">
                  <CardContent className="p-4">
                    <h3 className="font-medium text-sm mb-1">{product.name}</h3>
                    <p className="text-xs text-gray-600 mb-2">SKU: {product.sku}</p>
                    <p className="text-lg font-bold text-green-600 mb-2">
                      {formatCurrency(Number(product.price))}
                    </p>
                    <p className="text-xs text-gray-500 mb-3">
                      Stok: {product.stock_quantity}
                    </p>
                    <Button
                      onClick={() => addToCart(product)}
                      className="w-full"
                      size="sm"
                      disabled={product.stock_quantity <= 0}
                    >
                      <Plus className="h-4 w-4 mr-1" />
                      Tambah
                    </Button>
                  </CardContent>
                </Card>
              ))
            )}
          </div>
        </div>

        {/* Cart Section */}
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Keranjang Belanja</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {cart.length === 0 ? (
                <p className="text-gray-500 text-center py-8">Keranjang kosong</p>
              ) : (
                <>
                  <div className="space-y-2 max-h-64 overflow-y-auto">
                    {cart.map((item) => (
                      <div key={item.product.id} className="flex items-center justify-between p-2 border rounded">
                        <div className="flex-1">
                          <h4 className="font-medium text-sm">{item.product.name}</h4>
                          <p className="text-xs text-gray-600">
                            {formatCurrency(Number(item.product.price))}
                          </p>
                        </div>
                        <div className="flex items-center gap-2">
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => updateCartQuantity(item.product.id, item.quantity - 1)}
                          >
                            <Minus className="h-3 w-3" />
                          </Button>
                          <span className="w-8 text-center">{item.quantity}</span>
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => updateCartQuantity(item.product.id, item.quantity + 1)}
                          >
                            <Plus className="h-3 w-3" />
                          </Button>
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={() => removeFromCart(item.product.id)}
                          >
                            <Trash2 className="h-3 w-3" />
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>

                  <Separator />

                  <div className="space-y-2">
                    <div className="flex justify-between">
                      <span>Subtotal:</span>
                      <span>{formatCurrency(totals.subtotal)}</span>
                    </div>
                    {totals.discount > 0 && (
                      <div className="flex justify-between text-red-600">
                        <span>Diskon:</span>
                        <span>-{formatCurrency(totals.discount)}</span>
                      </div>
                    )}
                    <div className="flex justify-between font-bold text-lg">
                      <span>Total:</span>
                      <span>{formatCurrency(totals.total)}</span>
                    </div>
                  </div>
                </>
              )}
            </CardContent>
          </Card>

          {/* Customer and Payment */}
          <Card>
            <CardHeader>
              <CardTitle>Pembayaran</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <Label htmlFor="customerName">Nama Pelanggan (Opsional)</Label>
                <Input
                  id="customerName"
                  value={customerName}
                  onChange={(e) => setCustomerName(e.target.value)}
                  placeholder="Masukkan nama pelanggan"
                />
              </div>

              <div>
                <Label htmlFor="paymentMethod">Metode Pembayaran</Label>
                <Select value={paymentMethod} onValueChange={(value: any) => setPaymentMethod(value)}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="cash">Tunai</SelectItem>
                    <SelectItem value="card">Kartu</SelectItem>
                    <SelectItem value="transfer">Transfer</SelectItem>
                    <SelectItem value="credit">Kredit</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              {paymentMethod === 'cash' && (
                <>
                  <div>
                    <Label htmlFor="paymentReceived">Jumlah Bayar</Label>
                    <Input
                      id="paymentReceived"
                      type="number"
                      value={paymentReceived}
                      onChange={(e) => setPaymentReceived(Number(e.target.value))}
                      placeholder="0"
                    />
                  </div>
                  {paymentReceived > 0 && (
                    <div className="flex justify-between">
                      <span>Kembalian:</span>
                      <span className={change >= 0 ? 'text-green-600' : 'text-red-600'}>
                        {formatCurrency(Math.max(0, change))}
                      </span>
                    </div>
                  )}
                </>
              )}

              <Button
                onClick={handleCheckout}
                className="w-full"
                disabled={cart.length === 0 || createSaleMutation.isPending}
              >
                {createSaleMutation.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin mr-2" />
                ) : null}
                {paymentMethod === 'transfer' ? 'Bayar dengan Midtrans' : 'Checkout'}
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>

      {/* Reorder Dialog - Input */}
      <Dialog open={isReorderDialogOpen} onOpenChange={setIsReorderDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Transaksi Ulang</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label htmlFor="saleNumber">Nomor Penjualan</Label>
              <Input
                id="saleNumber"
                value={searchSaleNumber}
                onChange={(e) => setSearchSaleNumber(e.target.value)}
                placeholder="Masukkan nomor penjualan"
                onKeyPress={(e) => {
                  if (e.key === 'Enter') {
                    handleSearchSale();
                  }
                }}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsReorderDialogOpen(false)}>
              Batal
            </Button>
            <Button onClick={handleSearchSale} disabled={searchSaleMutation.isPending}>
              {searchSaleMutation.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin mr-2" />
              ) : (
                <Search className="h-4 w-4 mr-2" />
              )}
              Cari Transaksi
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reorder Dialog - Confirmation */}
      <Dialog open={isConfirmReorderOpen} onOpenChange={setIsConfirmReorderOpen}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Konfirmasi Transaksi Ulang</DialogTitle>
          </DialogHeader>
          
          {foundSale && (
            <div className="space-y-6">
              {/* Transaction Info */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Informasi Transaksi</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <p className="text-sm text-gray-600">Nomor Transaksi</p>
                      <p className="font-medium">{foundSale.sale_number}</p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-600">Tanggal</p>
                      <p className="font-medium">
                        {new Date(foundSale.created_at).toLocaleDateString('id-ID')}
                      </p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-600">Pelanggan</p>
                      <p className="font-medium">{foundSale.customer_name || 'Walk-in Customer'}</p>
                    </div>
                    <div>
                      <p className="text-sm text-gray-600">Total</p>
                      <p className="font-medium text-green-600">
                        {formatCurrency(Number(foundSale.total_amount))}
                      </p>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* Items */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Item Transaksi</CardTitle>
                </CardHeader>
                <CardContent>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Produk</TableHead>
                        <TableHead>Qty</TableHead>
                        <TableHead>Harga</TableHead>
                        <TableHead>Diskon</TableHead>
                        <TableHead>Subtotal</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {foundSale.sale_items?.map((item: any, index: number) => (
                        <TableRow key={index}>
                          <TableCell>{item.products?.name}</TableCell>
                          <TableCell>{item.quantity}</TableCell>
                          <TableCell>{formatCurrency(Number(item.unit_price))}</TableCell>
                          <TableCell>
                            {item.discount > 0 && (
                              <Badge variant="secondary">{item.discount}%</Badge>
                            )}
                          </TableCell>
                          <TableCell>{formatCurrency(Number(item.subtotal))}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>

              {/* Transaction Number Choice */}
              <Card>
                <CardHeader>
                  <CardTitle className="text-lg">Pilihan Nomor Transaksi</CardTitle>
                </CardHeader>
                <CardContent>
                  <RadioGroup
                    value={useOriginalNumber ? "original" : "new"}
                    onValueChange={(value) => setUseOriginalNumber(value === "original")}
                  >
                    <div className="flex items-center space-x-2">
                      <RadioGroupItem value="new" id="new" />
                      <Label htmlFor="new">🆕 Nomor baru (otomatis)</Label>
                    </div>
                    <div className="flex items-center space-x-2">
                      <RadioGroupItem value="original" id="original" />
                      <Label htmlFor="original">
                        🔄 Gunakan nomor asli: <strong>{foundSale.sale_number}</strong>
                      </Label>
                    </div>
                  </RadioGroup>
                </CardContent>
              </Card>

              {/* Stock Confirmation */}
              <Card className="border-amber-200 bg-amber-50">
                <CardHeader>
                  <CardTitle className="text-lg text-amber-800 flex items-center gap-2">
                    <AlertTriangle className="h-5 w-5" />
                    ⚠️ Konfirmasi Penyesuaian Stok
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="space-y-3">
                    <p className="text-amber-700">
                      <strong>Penting!</strong> Setelah melakukan transaksi ulang, Anda perlu:
                    </p>
                    <ul className="text-amber-700 space-y-1 ml-4">
                      <li>• <strong>Periksa stok fisik</strong> barang di gudang</li>
                      <li>• <strong>Sesuaikan jumlah stok</strong> jika diperlukan</li>
                      <li>• <strong>Pastikan ketersediaan</strong> sebelum menjual</li>
                    </ul>
                    <div className="flex items-center space-x-2 mt-4">
                      <Checkbox
                        id="stockConfirmation"
                        checked={stockConfirmationChecked}
                        onCheckedChange={setStockConfirmationChecked}
                      />
                      <Label htmlFor="stockConfirmation" className="text-amber-800 font-medium">
                        Saya akan memeriksa dan menyesuaikan stok barang setelah transaksi ini
                      </Label>
                    </div>
                  </div>
                </CardContent>
              </Card>
            </div>
          )}

          <DialogFooter>
            <Button variant="outline" onClick={() => setIsConfirmReorderOpen(false)}>
              Batal
            </Button>
            <Button
              onClick={handleConfirmReorder}
              disabled={!stockConfirmationChecked}
              className={!stockConfirmationChecked ? "opacity-50 cursor-not-allowed" : ""}
            >
              <RotateCcw className="h-4 w-4 mr-2" />
              Konfirmasi Transaksi Ulang
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Pre-checkout Dialog */}
      <PreCheckoutDialog
        open={isPreCheckoutOpen}
        onOpenChange={setIsPreCheckoutOpen}
        cart={cart}
        onCartUpdate={setCart}
        onProceedToPayment={handleProceedToPayment}
      />

      {/* Midtrans Payment Dialog */}
      <MidtransPayment
        open={isMidtransOpen}
        onOpenChange={setIsMidtransOpen}
        amount={totals.total}
        customerName={customerName}
        onPaymentSuccess={handleMidtransSuccess}
        onPaymentError={handleMidtransError}
      />
    </div>
  );
};

export default Cashier;