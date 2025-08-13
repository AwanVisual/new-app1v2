import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Calendar } from '@/components/ui/calendar';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { CalendarIcon, Download, BarChart3, Package, TrendingUp, TrendingDown, History } from 'lucide-react';
import { formatCurrency, formatDate } from '@/lib/utils';
import { format } from 'date-fns';
import { cn } from '@/lib/utils';

const Reports = () => {
  const [dateRange, setDateRange] = useState<{ from: Date; to: Date }>({
    from: new Date(new Date().getFullYear(), new Date().getMonth(), 1),
    to: new Date(),
  });
  const [selectedProduct, setSelectedProduct] = useState<string>('all');

  const { data: salesReport } = useQuery({
    queryKey: ['sales-report', dateRange],
    queryFn: async () => {
      const { data } = await supabase
        .from('sales')
        .select(`
          *,
          sale_items(
            *,
            products(name, sku)
          )
        `)
        .gte('created_at', dateRange.from.toISOString())
        .lte('created_at', dateRange.to.toISOString())
        .order('created_at', { ascending: false });
      
      return data || [];
    },
  });

  const { data: stockMovements } = useQuery({
    queryKey: ['stock-movements', dateRange, selectedProduct],
    queryFn: async () => {
      let query = supabase
        .from('stock_movements')
        .select(`
          *,
          products(name, sku, base_unit, pcs_per_base_unit)
        `)
        .gte('created_at', dateRange.from.toISOString())
        .lte('created_at', dateRange.to.toISOString())
        .order('created_at', { ascending: false });

      if (selectedProduct !== 'all') {
        query = query.eq('product_id', selectedProduct);
      }

      const { data } = await query;
      return data || [];
    },
  });

  const { data: inventoryReport } = useQuery({
    queryKey: ['inventory-report'],
    queryFn: async () => {
      const { data } = await supabase
        .from('products')
        .select(`
          *,
          categories(name)
        `)
        .order('name');
      
      return data || [];
    },
  });

  const { data: products } = useQuery({
    queryKey: ['products-list'],
    queryFn: async () => {
      const { data } = await supabase
        .from('products')
        .select('id, name')
        .order('name');
      return data || [];
    },
  });

  const totalSales = salesReport?.reduce((sum, sale) => sum + Number(sale.total_amount), 0) || 0;
  const totalTransactions = salesReport?.length || 0;
  const averageTransaction = totalTransactions > 0 ? totalSales / totalTransactions : 0;

  const exportToCSV = (data: any[], filename: string) => {
    if (!data.length) return;
    
    const headers = Object.keys(data[0]).join(',');
    const rows = data.map(row => Object.values(row).join(','));
    const csv = [headers, ...rows].join('\n');
    
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  };

  const getTransactionTypeIcon = (type: string) => {
    switch (type) {
      case 'inbound':
        return <TrendingUp className="h-4 w-4 text-green-600" />;
      case 'outbound':
        return <TrendingDown className="h-4 w-4 text-red-600" />;
      case 'adjustment':
        return <History className="h-4 w-4 text-blue-600" />;
      default:
        return <Package className="h-4 w-4" />;
    }
  };

  const getTransactionTypeBadge = (type: string) => {
    switch (type) {
      case 'inbound':
        return <Badge className="bg-green-100 text-green-800">Stock In</Badge>;
      case 'outbound':
        return <Badge className="bg-red-100 text-red-800">Stock Out</Badge>;
      case 'adjustment':
        return <Badge className="bg-blue-100 text-blue-800">Adjustment</Badge>;
      default:
        return <Badge variant="outline">{type}</Badge>;
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-2">
        <BarChart3 className="h-8 w-8" />
        <div>
          <h1 className="text-3xl font-bold">Reports</h1>
          <p className="text-gray-600">Sales and inventory analytics</p>
        </div>
      </div>

      {/* Date Range Selector */}
      <Card>
        <CardHeader>
          <CardTitle>Report Filters</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center space-x-4">
            <div>
              <Label>Date Range</Label>
              <div className="flex items-center space-x-2">
                <Popover>
                  <PopoverTrigger asChild>
                    <Button variant="outline" className="w-[240px] justify-start text-left font-normal">
                      <CalendarIcon className="mr-2 h-4 w-4" />
                      {dateRange.from ? format(dateRange.from, "PPP") : "Pick a date"}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0" align="start">
                    <Calendar
                      mode="single"
                      selected={dateRange.from}
                      onSelect={(date) => date && setDateRange(prev => ({ ...prev, from: date }))}
                      initialFocus
                    />
                  </PopoverContent>
                </Popover>
                <span>to</span>
                <Popover>
                  <PopoverTrigger asChild>
                    <Button variant="outline" className="w-[240px] justify-start text-left font-normal">
                      <CalendarIcon className="mr-2 h-4 w-4" />
                      {dateRange.to ? format(dateRange.to, "PPP") : "Pick a date"}
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-auto p-0" align="start">
                    <Calendar
                      mode="single"
                      selected={dateRange.to}
                      onSelect={(date) => date && setDateRange(prev => ({ ...prev, to: date }))}
                      initialFocus
                    />
                  </PopoverContent>
                </Popover>
              </div>
            </div>
            
            <div>
              <Label>Product Filter (Stock Movements)</Label>
              <Select value={selectedProduct} onValueChange={setSelectedProduct}>
                <SelectTrigger className="w-[200px]">
                  <SelectValue placeholder="Select product" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Products</SelectItem>
                  {products?.map((product) => (
                    <SelectItem key={product.id} value={product.id}>
                      {product.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
        </CardContent>
      </Card>

      <Tabs defaultValue="sales" className="space-y-4">
        <TabsList>
          <TabsTrigger value="sales">Sales Report</TabsTrigger>
          <TabsTrigger value="inventory">Inventory Report</TabsTrigger>
          <TabsTrigger value="stock-movements">Stock Movements</TabsTrigger>
        </TabsList>

        <TabsContent value="sales">
          <div className="grid gap-6 md:grid-cols-3 mb-6">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Sales</CardTitle>
                <BarChart3 className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{formatCurrency(totalSales)}</div>
                <p className="text-xs text-muted-foreground">
                  {totalTransactions} transactions
                </p>
              </CardContent>
            </Card>
            
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Avg Transaction</CardTitle>
                <TrendingUp className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{formatCurrency(averageTransaction)}</div>
              </CardContent>
            </Card>
            
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Transactions</CardTitle>
                <Package className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{totalTransactions}</div>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader>
              <div className="flex justify-between items-center">
                <CardTitle>Sales Transactions</CardTitle>
                <Button 
                  variant="outline" 
                  onClick={() => exportToCSV(salesReport || [], 'sales-report.csv')}
                >
                  <Download className="h-4 w-4 mr-2" />
                  Export CSV
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Sale Number</TableHead>
                    <TableHead>Customer</TableHead>
                    <TableHead>Items</TableHead>
                    <TableHead>Payment Method</TableHead>
                    <TableHead>Total</TableHead>
                    <TableHead>Date</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {salesReport?.map((sale) => (
                    <TableRow key={sale.id}>
                      <TableCell className="font-medium">{sale.sale_number}</TableCell>
                      <TableCell>{sale.customer_name || 'Walk-in'}</TableCell>
                      <TableCell>{sale.sale_items?.length || 0} items</TableCell>
                      <TableCell>
                        <Badge variant="outline">{sale.payment_method}</Badge>
                      </TableCell>
                      <TableCell>{formatCurrency(Number(sale.total_amount))}</TableCell>
                      <TableCell>{formatDate(sale.created_at!)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="inventory">
          <Card>
            <CardHeader>
              <div className="flex justify-between items-center">
                <CardTitle>Current Inventory Status</CardTitle>
                <Button 
                  variant="outline" 
                  onClick={() => exportToCSV(inventoryReport || [], 'inventory-report.csv')}
                >
                  <Download className="h-4 w-4 mr-2" />
                  Export CSV
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Product</TableHead>
                    <TableHead>SKU</TableHead>
                    <TableHead>Category</TableHead>
                    <TableHead>Current Stock</TableHead>
                    <TableHead>Initial Stock</TableHead>
                    <TableHead>Stock Added</TableHead>
                    <TableHead>Stock Reduced</TableHead>
                    <TableHead>Movements</TableHead>
                    <TableHead>Value</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {inventoryReport?.map((product) => (
                    <TableRow key={product.id}>
                      <TableCell>
                        <div>
                          <div className="font-medium">{product.name}</div>
                          <div className="text-sm text-muted-foreground">
                            {formatCurrency(Number(product.price))} / {product.base_unit}
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>{product.sku}</TableCell>
                      <TableCell>{product.categories?.name || 'No Category'}</TableCell>
                      <TableCell>
                        <div>
                          <div className="font-medium">
                            {product.stock_quantity} {product.base_unit}
                          </div>
                          <div className="text-sm text-muted-foreground">
                            ({product.stock_pcs || 0} pcs)
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div>
                          <div className="text-blue-600">
                            {product.initial_stock_quantity || 0} {product.base_unit}
                          </div>
                          <div className="text-sm text-blue-500">
                            ({product.initial_stock_pcs || 0} pcs)
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-green-600 font-medium">
                          +{product.total_stock_added || 0} pcs
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-red-600 font-medium">
                          -{product.total_stock_reduced || 0} pcs
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">
                          {product.stock_movement_count || 0}x
                        </Badge>
                      </TableCell>
                      <TableCell>
                        {formatCurrency(Number(product.price) * product.stock_quantity)}
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
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="stock-movements">
          <div className="grid gap-6 md:grid-cols-4 mb-6">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Movements</CardTitle>
                <History className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{stockMovements?.length || 0}</div>
                <p className="text-xs text-muted-foreground">In selected period</p>
              </CardContent>
            </Card>
            
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Stock In</CardTitle>
                <TrendingUp className="h-4 w-4 text-green-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-green-600">
                  {stockMovements?.filter(m => m.transaction_type === 'inbound').length || 0}
                </div>
                <p className="text-xs text-muted-foreground">Inbound movements</p>
              </CardContent>
            </Card>
            
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Stock Out</CardTitle>
                <TrendingDown className="h-4 w-4 text-red-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-red-600">
                  {stockMovements?.filter(m => m.transaction_type === 'outbound').length || 0}
                </div>
                <p className="text-xs text-muted-foreground">Outbound movements</p>
              </CardContent>
            </Card>
            
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Adjustments</CardTitle>
                <History className="h-4 w-4 text-blue-600" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold text-blue-600">
                  {stockMovements?.filter(m => m.transaction_type === 'adjustment').length || 0}
                </div>
                <p className="text-xs text-muted-foreground">Stock adjustments</p>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader>
              <div className="flex justify-between items-center">
                <CardTitle>Stock Movement History</CardTitle>
                <Button 
                  variant="outline" 
                  onClick={() => exportToCSV(stockMovements || [], 'stock-movements.csv')}
                >
                  <Download className="h-4 w-4 mr-2" />
                  Export CSV
                </Button>
              </div>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Product</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Quantity</TableHead>
                    <TableHead>Unit</TableHead>
                    <TableHead>Reference</TableHead>
                    <TableHead>Notes</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {stockMovements?.map((movement) => (
                    <TableRow key={movement.id}>
                      <TableCell>{formatDate(movement.created_at!)}</TableCell>
                      <TableCell>
                        <div>
                          <div className="font-medium">{movement.products?.name}</div>
                          <div className="text-sm text-muted-foreground">{movement.products?.sku}</div>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center space-x-2">
                          {getTransactionTypeIcon(movement.transaction_type)}
                          {getTransactionTypeBadge(movement.transaction_type)}
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className={cn(
                          "font-medium",
                          movement.transaction_type === 'inbound' ? "text-green-600" : "text-red-600"
                        )}>
                          {movement.transaction_type === 'inbound' ? '+' : '-'}{movement.quantity}
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">
                          {movement.unit_type === 'pcs' ? 'pcs' : movement.products?.base_unit || 'unit'}
                        </Badge>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm">
                          {movement.reference_number || '-'}
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="text-sm text-muted-foreground">
                          {movement.notes || '-'}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
};

export default Reports;