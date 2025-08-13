import { useState, useEffect } from "react";
import { useQuery as useReactQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import {
  Plus,
  Minus,
  ShoppingCart,
  Trash2,
  Receipt,
  Calculator,
  Percent,
  Package,
} from "lucide-react";
import { useToast } from "@/hooks/use-toast";
import { formatCurrency } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import PreCheckoutDialog from "@/components/PreCheckoutDialog";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";

interface CartItem {
  product: any;
  quantity: number;
  unitType: 'pcs' | 'base_unit'; // Simple unit selection
  customDiscount: number; // Percentage discount for this specific item
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
  const [cart, setCart] = useState<CartItem[]>([]);
  const [customerName, setCustomerName] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<string>("cash");
  const [paymentReceived, setPaymentReceived] = useState<number>(0);
  const [bankDetails, setBankDetails] = useState("");
  const [showPreCheckout, setShowPreCheckout] = useState(false);
  const [receiptConfig, setReceiptConfig] = useState<ReceiptFieldsConfig>({
    showAmount: true,
    showDppFaktur: false,
    showDiscount: false,
    showPpn11: false,
    discountPercentage: 0,
    useSpecialCustomerCalculation: false,
  });
  const [selectedCashier, setSelectedCashier] = useState<string>("");
  const [reorderDialogOpen, setReorderDialogOpen] = useState(false);
  const [reorderSaleNumber, setReorderSaleNumber] = useState("");
  const [foundSale, setFoundSale] = useState<any>(null);
  const [useOriginalNumber, setUseOriginalNumber] = useState(false);
  const [stockWarningChecked, setStockWarningChecked] = useState(false);




  const searchSaleMutation = useMutation({
    mutationFn: async (saleNumber: string) => {
      const { data, error } = await supabase
        .from('sales')
        .select(`
          *,
          sale_items (
            *,
            product:products (*)
          )
        `)
        .eq('sale_number', saleNumber)
        .single();
      
      if (error) throw error;
      return data;
    },
    onSuccess: (data) => {
      setFoundSale(data);
      setIsConfirmReorderOpen(true);
      toast({
        title: "Transaksi ditemukan",
        description: `Transaksi ${data.sale_number} berhasil ditemukan`,
      });
    },
    onError: (error: any) => {
      toast({
        title: "Error",
        description: error.message === 'No rows returned' 
          ? "Nomor penjualan tidak ditemukan" 
          : error.message,
        variant: "destructive",
      });
    },
  });
  const [showReorderConfirm, setShowReorderConfirm] = useState(false);

  // Update payment received when payment method changes
  useEffect(() => {
    if (paymentMethod !== "cash") {
      const totalAmount = calculateFinalTotal();
      setPaymentReceived(totalAmount);
    } else {
      setPaymentReceived(0);
    }
  }, [paymentMethod, cart]);

  const calculateDetailedPricing = (item: CartItem) => {
    const price = item.unitType === 'pcs' 
      ? Number(item.product.price_per_pcs || item.product.price)
      : Number(item.product.price);
    const quantity = item.quantity;
    const itemDiscount = item.customDiscount || 0;

    if (receiptConfig.useSpecialCustomerCalculation) {
      // Special customer calculation (existing logic)
      const amount = quantity * price;
      const dpp11 = (100 / 111) * price;
      const discount = (itemDiscount / 100) * dpp11;
      const dppFaktur = dpp11 - discount;
      const dppLain = (11 / 12) * dppFaktur;

      // PPN 11% and PPN 12% must return the same value
      const ppn11 = 0.11 * dppFaktur;
      const ppn12 = ppn11; // Same value as PPN 11%

      return {
        amount,
        dpp11: dpp11 * quantity,
        discount: discount * quantity,
        dppFaktur: dppFaktur * quantity,
        dppLain: dppLain * quantity,
        ppn11: ppn11 * quantity,
        ppn12: ppn12 * quantity,
        finalItemTotal: (dppFaktur + ppn11) * quantity,
      };
    } else {
      // Simple discount calculation - direct price reduction
      const discountAmount = (itemDiscount / 100) * price;
      const discountedPrice = price - discountAmount;
      const finalItemTotal = discountedPrice * quantity;
      
      return {
        amount: quantity * price,
        dpp11: 0,
        discount: discountAmount * quantity,
        dppFaktur: discountedPrice * quantity,
        dppLain: 0,
        ppn11: 0,
        ppn12: 0,
        finalItemTotal: finalItemTotal,
      };
    }
  };

  const { data: products } = useReactQuery({
    queryKey: ["products"],
    queryFn: async () => {
      const { data } = await supabase
        .from("products")
        .select("*")
        .eq("is_active", true)
        .gt("stock_quantity", 0);
      return data || [];
    },
  });

  const { data: settings } = useReactQuery({
    queryKey: ["settings"],
    queryFn: async () => {
      const { data } = await supabase.from("settings").select("*");
      const settingsMap =
        data?.reduce(
          (acc, setting) => {
            acc[setting.key] = setting.value;
            return acc;
          },
          {} as Record<string, string>,
        ) || {};
      return settingsMap;
    },
  });

  const { data: cashiers } = useReactQuery({
    queryKey: ["cashiers"],
    queryFn: async () => {
      const { data } = await supabase
        .from("profiles")
        .select("id, full_name")
        .in("role", ["cashier", "admin", "stockist"])
        .order("full_name");
      return data || [];
    },
  });

  // Get product units for each product
  const { data: productUnits } = useReactQuery({
    queryKey: ["product-units-all"],
    queryFn: async () => {
      const { data } = await supabase
        .from("product_units")
        .select("*")
        .eq("is_active", true);
      return data || [];
    },
  });

  // Function to check stock availability and provide detailed messages
  const checkStockAvailability = (product: any, unitType: 'pcs' | 'base_unit', quantity: number) => {
    const stockInBaseUnit = product.stock_quantity; // Stock in base units (dus, box, etc)
    const stockInPcs = product.stock_pcs || 0; // Stock in pieces
    const pcsPerBaseUnit = product.pcs_per_base_unit || 1;
    
    if (unitType === 'pcs') {
      // Buying in pieces
      if (quantity <= stockInPcs) {
        return { available: true, message: '' };
      } else {
        return { 
          available: false, 
          message: `Stok tidak cukup. Tersedia: ${stockInPcs} pcs (${Math.floor(stockInBaseUnit)} ${product.base_unit})` 
        };
      }
    } else {
      // Buying in base units (dus, box, etc)
      const requiredPcs = quantity * pcsPerBaseUnit;
      
      // Check if we have enough pieces for the requested base units
      if (stockInPcs >= requiredPcs) {
        return { available: true, message: '' };
      } else {
        return {
          available: false,
          message: `Tidak bisa beli ${quantity} ${product.base_unit}. Butuh ${requiredPcs} pcs tapi hanya tersedia ${stockInPcs} pcs.`
        };
      }
    }
  };

  const subtotal = cart.reduce(
    (sum, item) => sum + Number(item.product.price) * item.quantity,
    0,
  );

  // Calculate final total using DPP Faktur + PPN 11% with per-item discounts
  const calculateFinalTotal = () => {
    return cart.reduce((sum, item) => {
      const itemCalc = calculateDetailedPricing(item);
      return sum + itemCalc.finalItemTotal;
    }, 0);
  };

  const total = calculateFinalTotal();
  const effectivePaymentReceived = paymentMethod !== "cash" ? total : paymentReceived;
  const change = effectivePaymentReceived - total;

  // Get available units for a product
  const getProductUnits = (productId: string) => {
    return productUnits?.filter(unit => unit.product_id === productId) || [];
  };

  const addToCart = (product: any) => {
    setCart((prev) => {
      const existing = prev.find((item) => item.product.id === product.id);
      
      if (existing) {
        // Check stock availability based on unit type
        const newQuantity = existing.quantity + 1;
        const isStockAvailable = checkStockAvailability(product, existing.unitType, newQuantity);
        
        if (isStockAvailable.available) {
          return prev.map((item) =>
            item.product.id === product.id
              ? { ...item, quantity: newQuantity }
              : item,
          );
        } else {
          toast({
            title: "Stok Tidak Cukup",
            description: isStockAvailable.message,
            variant: "destructive",
          });
          return prev;
        }
      }
      
      // Always allow adding to cart, but start with appropriate unit type
      const pcsPerBaseUnit = product.pcs_per_base_unit || 1;
      const hasEnoughPcsForOneBaseUnit = (product.stock_pcs || 0) >= pcsPerBaseUnit;
      const hasPcsStock = (product.stock_pcs || 0) > 0;
      
      // If no stock at all, don't allow adding
      if (!hasPcsStock) {
        toast({
          title: "Stok Habis",
          description: "Produk ini sudah habis",
          variant: "destructive",
        });
        return prev;
      }
      
      // Start with base_unit if we have enough pcs for at least one base unit, otherwise pcs
      const initialUnitType = hasEnoughPcsForOneBaseUnit ? 'base_unit' : 'pcs';
      
      return [...prev, { product, quantity: 1, unitType: initialUnitType, customDiscount: 0 }];
    });
  };

  const updateQuantity = (productId: string, newQuantity: number) => {
    if (newQuantity <= 0) {
      removeFromCart(productId);
      return;
    }

    setCart((prev) =>
      prev.map((item) => {
        if (item.product.id === productId) {
          const isStockAvailable = checkStockAvailability(item.product, item.unitType, newQuantity);
          
          if (isStockAvailable.available) {
            return { ...item, quantity: newQuantity };
          } else {
            toast({
              title: "Error",
              description: isStockAvailable.message,
              variant: "destructive",
            });
          }
        }
        return item;
      }),
    );
  };

  const updateItemUnitType = (productId: string, newUnitType: 'pcs' | 'base_unit') => {
    setCart((prev) => {
      return prev.map((item) => {
        if (item.product.id === productId) {
          // Check if current quantity is valid for new unit type
          const isStockAvailable = checkStockAvailability(item.product, newUnitType, item.quantity);
          
          if (!isStockAvailable.available) {
            toast({
              title: "Stok Tidak Cukup",
              description: isStockAvailable.message,
              variant: "destructive",
            });
            return item; // Keep current unit type
          }
          
          return { ...item, unitType: newUnitType };
        }
        return item;
      });
    });
  };

  const updateItemDiscount = (productId: string, discount: number) => {
    setCart((prev) =>
      prev.map((item) =>
        item.product.id === productId
          ? { ...item, customDiscount: Math.max(0, Math.min(100, discount)) }
          : item,
      ),
    );
  };

  const removeFromCart = (productId: string) => {
    setCart((prev) => prev.filter((item) => item.product.id !== productId));
  };

  const handlePreCheckoutProceed = (config: ReceiptFieldsConfig) => {
    setReceiptConfig(config);
    setShowPreCheckout(false);
    if (config.useSpecialCustomerCalculation) {
      toast({
        title: "Special Customer Pricing Applied",
        description: `Advanced pricing calculation enabled. You can now complete the sale with the configured pricing.`,
      });
    } else {
      toast({
        title: "Simple Discount Applied",
        description: `Direct price discount enabled. Item discounts will be applied directly to prices.`,
      });
    }
  };

  const handleConfirmReorder = () => {
    if (!stockWarningChecked) {
      toast({
        title: "Peringatan",
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
    const newCartItems: CartItem[] = foundSale.sale_items.map((saleItem: any) => ({
      product: saleItem.products,
      quantity: saleItem.quantity,
      unitType: saleItem.unit_type || 'base_unit',
      customDiscount: saleItem.discount || 0,
    }));
    
    setCart(newCartItems);
    setCustomerName(foundSale.customer_name || '');
    
    // Close dialogs and reset states
    setReorderDialogOpen(false);
    setIsConfirmReorderOpen(false);
    setFoundSale(null);
    setSearchSaleNumber('');
    setUseOriginalNumber(false);
    setStockWarningChecked(false);
    
    toast({
      title: "Berhasil",
      description: `${foundSale.sale_items.length} item berhasil ditambahkan ke keranjang`,
    });
  };

  const processSaleMutation = useMutation({
    mutationFn: async () => {
      if (cart.length === 0) throw new Error("Cart is empty");

      const totalAmount = total;

      // For non-cash payments, ensure payment received equals total amount
      const effectivePaymentReceived = paymentMethod !== "cash" ? totalAmount : paymentReceived;

      console.log("Payment validation:", {
        paymentReceived: effectivePaymentReceived,
        totalAmount,
        paymentMethod,
        sufficient: effectivePaymentReceived >= totalAmount,
      });

      if (effectivePaymentReceived < totalAmount) {
        throw new Error(
          `Pembayaran kurang. Dibutuhkan: ${formatCurrency(totalAmount)}, Diterima: ${formatCurrency(effectivePaymentReceived)}`,
        );
      }

      // Generate sale number
      const { data: saleNumber } = await supabase.rpc("generate_sale_number");

      // Create sale record with bank details if applicable
      const saleData: any = {
        sale_number: saleNumber,
        customer_name: customerName || null,
        subtotal,
        tax_amount: 0,
        total_amount: totalAmount,
        payment_method: paymentMethod as any,
        payment_received: effectivePaymentReceived,
        change_amount: Math.max(0, effectivePaymentReceived - totalAmount),
        created_by: user?.id,
        cashier_id: user?.id,
        notes: JSON.stringify({
          sales_person: selectedCashier || null,
          bank_details: bankDetails || null,
          discount_config: {
            use_special_customer_calculation: receiptConfig.useSpecialCustomerCalculation,
            global_discount_percentage: receiptConfig.discountPercentage,
            show_amount: receiptConfig.showAmount,
            show_dpp_faktur: receiptConfig.showDppFaktur,
            show_discount: receiptConfig.showDiscount,
            show_ppn11: receiptConfig.showPpn11
          }
        }),
        invoice_status: paymentMethod === 'credit' ? 'belum_bayar' : 'lunas',
      };

      

      const { data: sale, error: saleError } = await supabase
        .from("sales")
        .insert(saleData)
        .select()
        .single();

      if (saleError) throw saleError;
      if (!sale) throw new Error("Failed to create sale record");

      // Create sale items with individual discount information
      const saleItems = cart.map((item) => ({
        sale_id: sale.id,
        product_id: item.product.id,
        unit_id: null, // Keep null for now, bisa dikembangkan nanti
        unit_type: item.unitType, // Simpan unit type (pcs atau base_unit)
        quantity: item.quantity,
        unit_price: item.unitType === 'pcs' 
          ? Number(item.product.price_per_pcs || item.product.price)
          : Number(item.product.price),
        subtotal: (item.unitType === 'pcs' 
          ? Number(item.product.price_per_pcs || item.product.price)
          : Number(item.product.price)) * item.quantity,
        discount: item.customDiscount, // Save the item discount percentage
      }));

      const { error: itemsError } = await supabase
        .from("sale_items")
        .insert(saleItems);

      if (itemsError) throw itemsError;

      // Create stock movements for each item
      const stockMovements = cart.map((item) => ({
        product_id: item.product.id,
        unit_id: null, // Keep null for now
        unit_type: item.unitType, // Simpan unit type untuk stock movement
        transaction_type: "outbound" as any,
        quantity: item.quantity,
        reference_number: saleNumber,
        notes: `Sale: ${saleNumber}`,
        created_by: user?.id,
      }));

      const { error: stockError } = await supabase
        .from("stock_movements")
        .insert(stockMovements);

      if (stockError) throw stockError;

      return sale;
    },
    onSuccess: (sale) => {
      queryClient.invalidateQueries({ queryKey: ["products"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard-stats"] });
      setCart([]);
      setCustomerName("");
      setPaymentReceived(0);
      setBankDetails("");
      setSelectedCashier("");
      toast({
        title: "Success",
        description: `Sale ${sale.sale_number} completed successfully!`,
      });

      // Generate and download receipt with updated settings
      generateReceipt(sale);
    },
    onError: (error: any) => {
      console.error("Sale processing error:", error);
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const generateReceipt = async (sale: any) => {
    const logoUrl = settings?.company_logo ? settings.company_logo : "";
    const storeName = settings?.store_name || "";
    const storeAddress = settings?.store_address || "";
    const storePhone = settings?.store_phone || "";
    const storeEmail = settings?.store_email || "";
    const storeWebsite = settings?.store_website || "";
    const receiptHeader = settings?.receipt_header || "";
    const receiptFooter = settings?.receipt_footer || "";

    // Get sales name
    const salesName = selectedCashier || user?.email || "Unknown";

    // Calculate detailed pricing totals for receipt using individual item discounts
    const detailedTotals = cart.reduce(
      (totals, item) => {
        const itemCalc = calculateDetailedPricing(item);
        return {
          amount: totals.amount + itemCalc.amount,
          discount: totals.discount + itemCalc.discount,
          dppFaktur: totals.dppFaktur + itemCalc.dppFaktur,
          ppn11: totals.ppn11 + itemCalc.ppn11,
        };
      },
      { amount: 0, discount: 0, dppFaktur: 0, ppn11: 0 },
    );

    // Import jsPDF dynamically
    const { jsPDF } = await import('jspdf');
    
    // Create PDF with custom 24x16cm format (landscape)
    const pdf = new jsPDF({
      orientation: 'landscape',
      unit: 'cm',
      format: [16, 24] // 16cm height x 24cm width
    });

    // Set font
    pdf.setFont('helvetica');

    let yPosition = 1.0;
    const leftMargin = 0.5; // Left margin for 24cm width
    const rightMargin = 23.5; // Right margin for 24cm width
    const pageWidth = 24; // 24cm width
    const pageHeight = 16; // 16cm height
    const contentWidth = pageWidth - 1.0; // Content width
    const maxYPosition = pageHeight - 1.0;

    // Function to check if we need a new page
    const checkPageBreak = (requiredSpace: number = 0.5) => {
      if (yPosition + requiredSpace > maxYPosition) {
        pdf.addPage();
        yPosition = 1.0;
        return true;
      }
      return false;
    };

    // Header with logo and company info
    if (logoUrl) {
      try {
        // Create a new image to get natural dimensions
        const img = new Image();
        img.crossOrigin = 'anonymous';
        
        await new Promise((resolve, reject) => {
          img.onload = resolve;
          img.onerror = reject;
          img.src = logoUrl;
        });
        
        // Calculate logo dimensions maintaining aspect ratio
        const maxLogoWidth = 3.0;
        const maxLogoHeight = 2.0;
        const aspectRatio = img.naturalWidth / img.naturalHeight;
        
        let logoWidth, logoHeight;
        
        // Maintain aspect ratio without stretching
        if (aspectRatio > 1) {
          // Logo is wider - fit to width
          logoWidth = Math.min(maxLogoWidth, maxLogoHeight * aspectRatio);
          logoHeight = logoWidth / aspectRatio;
        } else {
          // Logo is taller or square - fit to height
          logoHeight = Math.min(maxLogoHeight, maxLogoWidth / aspectRatio);
          logoWidth = logoHeight * aspectRatio;
        }
        
        pdf.addImage(logoUrl, 'PNG', leftMargin, yPosition, logoWidth, logoHeight, undefined, 'FAST');
      } catch (error) {
        console.log('Logo could not be added to PDF');
      }
    }

    // Company info on the right
    checkPageBreak(1.5);
    pdf.setFontSize(18); // Adjusted font for 24x16cm
    pdf.setFont('helvetica', 'bold');
    pdf.text('INVOICE', rightMargin, yPosition + 0.3, { align: 'right' });

    yPosition += 1.0;
    pdf.setFontSize(10); // Smaller font for company info
    pdf.setFont('helvetica', 'normal');
    if (storeName) {
      checkPageBreak(0.4);
      pdf.text(storeName, pageWidth - 0.8, yPosition, { align: 'right' });
      yPosition += 0.4;
    }
    if (storeAddress) {
      checkPageBreak(0.4);
      pdf.text(storeAddress, pageWidth - 0.8, yPosition, { align: 'right' });
      yPosition += 0.4;
    }
    if (storePhone) {
      checkPageBreak(0.4);
      pdf.text(storePhone, pageWidth - 0.8, yPosition, { align: 'right' });
      yPosition += 0.4;
    }
    if (storeEmail) {
      checkPageBreak(0.4);
      pdf.text(storeEmail, pageWidth - 0.8, yPosition, { align: 'right' });
      yPosition += 0.4;
    }
    if (storeWebsite) {
      checkPageBreak(0.4);
      pdf.text(storeWebsite, pageWidth - 0.8, yPosition, { align: 'right' });
      yPosition += 0.4;
    }

    // Line separator
    yPosition += 0.4;
    checkPageBreak(0.8);
    pdf.setLineWidth(0.02);
    pdf.line(leftMargin, yPosition, rightMargin, yPosition);
    yPosition += 0.4;

    // Invoice details
    checkPageBreak(1.6);
    pdf.setFontSize(12);
    pdf.setFont('helvetica', 'bold');
    pdf.text(`NO INVOICE: ${sale.sale_number}`, leftMargin, yPosition);
    yPosition += 0.5;
    checkPageBreak(0.5);
    pdf.text(`TANGGAL: ${new Date(sale.created_at).toLocaleDateString("id-ID")}`, leftMargin, yPosition);
    yPosition += 0.5;
    if (sale.customer_name) {
      checkPageBreak(0.5);
      pdf.text(`KEPADA: ${sale.customer_name}`, leftMargin, yPosition);
      yPosition += 0.5;
    }
    checkPageBreak(0.5);
    pdf.text(`NAMA SALES: ${salesName}`, leftMargin, yPosition);
    yPosition += 0.6;

    // Table header
    checkPageBreak(0.8);
    pdf.setFontSize(10); // Adjusted header font for landscape
    pdf.setFont('helvetica', 'bold');
    pdf.text('KETERANGAN', leftMargin, yPosition);
    pdf.text('QTY', leftMargin + 12.0, yPosition, { align: 'center' }); // Adjusted spacing for 24cm width
    pdf.text('HARGA', leftMargin + 16.0, yPosition, { align: 'right' }); // Adjusted positioning
    pdf.text('DISC', leftMargin + 19.0, yPosition, { align: 'right' }); // Adjusted spacing
    pdf.text('TOTAL', leftMargin + 22.0, yPosition, { align: 'right' }); // Adjusted for 24cm width

    yPosition += 0.2;
    pdf.line(leftMargin, yPosition, rightMargin, yPosition);
    yPosition += 0.4;

    // Table items
    pdf.setFont('helvetica', 'normal');
    pdf.setFontSize(9); // Adjusted font size for landscape
    cart.forEach((item) => {
      checkPageBreak(0.5);
      const itemCalc = calculateDetailedPricing(item);
      
      // Product name (wrap if too long) - adjusted for 24cm width
      const productName = item.product.name.length > 50 ? 
        item.product.name.substring(0, 50) + '...' : 
        item.product.name;
      
      // Display quantity with unit
      const quantityDisplay = item.unitType === 'pcs' 
        ? `${item.quantity} pcs`
        : `${item.quantity} ${item.product.base_unit}`;
      
      // Use correct price based on unit type
      const unitPrice = item.unitType === 'pcs' 
        ? Number(item.product.price_per_pcs || item.product.price)
        : Number(item.product.price);
      pdf.text(productName, leftMargin, yPosition);
      pdf.text(quantityDisplay, leftMargin + 12.0, yPosition, { align: 'center' });
      pdf.text(formatCurrency(unitPrice), leftMargin + 16.0, yPosition, { align: 'right' });
      
      if (item.customDiscount > 0) {
        pdf.text(`${item.customDiscount}%`, leftMargin + 19.0, yPosition, { align: 'right' });
      } else {
        pdf.text('-', leftMargin + 19.0, yPosition, { align: 'right' });
      }
      
      pdf.text(formatCurrency(itemCalc.finalItemTotal), leftMargin + 22.0, yPosition, { align: 'right' });
      yPosition += 0.5; // Adjusted line spacing
    });

    // Line separator
    yPosition += 0.3;
    checkPageBreak(1.8);
    pdf.line(leftMargin, yPosition, rightMargin, yPosition);
    yPosition += 0.5;

    // Payment note section
    checkPageBreak(1.2);
    pdf.setFontSize(10);
    pdf.setFont('helvetica', 'bold');
    pdf.text('CATATAN PEMBAYARAN:', leftMargin, yPosition);
    yPosition += 0.5;
    checkPageBreak(0.4);
    pdf.setFont('helvetica', 'normal');
    pdf.text(settings?.payment_note_line1 || `Harga BCA : ${formatCurrency(Math.round(detailedTotals.dppFaktur / cart.length))}/PUTRA INDRAWAN`, leftMargin, yPosition);
    yPosition += 0.4;
    checkPageBreak(0.4);
    pdf.text(settings?.payment_note_line2 || "No. Rekening: 7840656905", leftMargin, yPosition);

    // Totals section
    yPosition += 0.8;
    checkPageBreak(2.0);
    pdf.setFontSize(10); // Adjusted font size for totals
    pdf.setFont('helvetica', 'normal');

    if (receiptConfig.showAmount) {
      pdf.text('SUB TOTAL:', leftMargin + 14.0, yPosition);
      pdf.text(formatCurrency(detailedTotals.amount), rightMargin - 0.5, yPosition, { align: 'right' });
      yPosition += 0.5;
    }

    if (detailedTotals.discount > 0) {
      checkPageBreak(0.5);
      pdf.text('Total Discount:', leftMargin + 14.0, yPosition);
      pdf.text(`-${formatCurrency(detailedTotals.discount)}`, rightMargin - 0.5, yPosition, { align: 'right' });
      yPosition += 0.5;
    }

    if (receiptConfig.showDppFaktur) {
      checkPageBreak(0.5);
      pdf.text('DPP Faktur:', leftMargin + 14.0, yPosition);
      pdf.text(formatCurrency(detailedTotals.dppFaktur), rightMargin - 0.5, yPosition, { align: 'right' });
      yPosition += 0.5;
    }

    if (receiptConfig.showPpn11) {
      checkPageBreak(0.5);
      pdf.text('PPN 11%:', leftMargin + 14.0, yPosition);
      pdf.text(formatCurrency(detailedTotals.ppn11), rightMargin - 0.5, yPosition, { align: 'right' });
      yPosition += 0.5;
    }

    // Final total
    yPosition += 0.4;
    checkPageBreak(0.7);
    pdf.line(leftMargin + 14.0, yPosition, rightMargin - 0.5, yPosition);
    yPosition += 0.5;
    pdf.setFont('helvetica', 'bold');
    pdf.setFontSize(12); // Adjusted total font size
    pdf.text('TOTAL:', leftMargin + 14.0, yPosition);
    pdf.text(formatCurrency(total), rightMargin - 0.5, yPosition, { align: 'right' });

    // Footer
    if (receiptHeader || receiptFooter) {
      yPosition += 1.0;
      checkPageBreak(1.0);
      pdf.line(leftMargin, yPosition, rightMargin, yPosition);
      yPosition += 0.4;
      pdf.setFont('helvetica', 'normal');
      pdf.setFontSize(9);
      if (receiptHeader) {
        checkPageBreak(0.4);
        pdf.text(receiptHeader, pageWidth / 2, yPosition, { align: 'center' });
        yPosition += 0.4;
      }
      if (receiptFooter) {
        checkPageBreak(0.4);
        pdf.text(receiptFooter, pageWidth / 2, yPosition, { align: 'center' });
      }
    }

    // Save PDF
    pdf.save(`Invoice-${sale.sale_number}.pdf`);
    
    // Auto-print the PDF with better user control
    try {
      const pdfBlob = pdf.output('blob');
      const pdfUrl = URL.createObjectURL(pdfBlob);
      
      // Show user-friendly notification
      toast({
        title: "PDF Generated Successfully",
        description: "PDF will open in a new window for printing. Please allow popups if prompted.",
        duration: 3000,
      });
      
      // Open print window with better timing control
      const printWindow = window.open(pdfUrl, '_blank', 'width=1200,height=900,scrollbars=yes,resizable=yes,menubar=yes,toolbar=yes');
      if (printWindow) {
        // Wait for PDF to fully load before showing print dialog
        printWindow.addEventListener('load', () => {
          setTimeout(() => {
            try {
              printWindow.focus();
              printWindow.print();
              
              // Show helpful message after print dialog appears
              setTimeout(() => {
                if (!printWindow.closed) {
                  toast({
                    title: "Print Dialog Ready",
                    description: "Select your printer and settings. The window will remain open for your convenience.",
                    duration: 10000,
                  });
                }
              }, 3000);
              
            } catch (e) {
              console.log('Print dialog error:', e);
              toast({
                title: "Stok Tidak Cukup",
                description: "Please use Ctrl+P or Cmd+P in the opened window to print.",
                duration: 6000,
              });
            }
          }, 3000); // Wait 3 seconds for PDF to fully render
        });
        
        // Clean up URL when window is closed
        const checkClosed = setInterval(() => {
          if (printWindow.closed) {
            clearInterval(checkClosed);
            URL.revokeObjectURL(pdfUrl);
          }
        }, 1000);
        
        // Failsafe cleanup after 10 minutes
        setTimeout(() => {
          clearInterval(checkClosed);
          URL.revokeObjectURL(pdfUrl);
        }, 600000);
        
      } else {
        // Popup blocked - show helpful message
        toast({
          title: "Popup Blocked",
          description: "Please allow popups for this site, then try again. PDF has been downloaded as backup.",
          variant: "destructive",
          duration: 8000,
        });
      }
    } catch (error) {
      console.log('Print failed:', error);
      toast({
        title: "Print Error",
        description: "Could not open print window. PDF has been downloaded to your computer instead.",
        variant: "destructive",
        duration: 6000,
      });
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold text-gray-900">Cashier</h1>
        
        {/* Reorder Button */}
        <Dialog open={reorderDialogOpen} onOpenChange={setReorderDialogOpen}>
          <DialogTrigger asChild>
            <Button variant="outline" className="flex items-center gap-2">
              <Receipt className="h-4 w-4" />
              Transaksi Ulang
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Transaksi Ulang</DialogTitle>
            </DialogHeader>
            <div className="space-y-4">
              <div>
                <Label htmlFor="reorderSaleNumber">Nomor Penjualan</Label>
                <Input
                  id="reorderSaleNumber"
                  value={reorderSaleNumber}
                  onChange={(e) => setReorderSaleNumber(e.target.value)}
                  placeholder="Masukkan nomor penjualan (contoh: SALE-20250101-001)"
                />
              </div>
              <div className="flex justify-end space-x-2">
                <Button 
                  variant="outline" 
                  onClick={() => {
                    setReorderDialogOpen(false);
                    setReorderSaleNumber("");
                  }}
                >
                  Batal
                </Button>
                <Button 
                  //onClick={handleSearchSale}
                  disabled={searchSaleMutation.isPending}
                >
                  {searchSaleMutation.isPending ? "Mencari..." : "Cari Transaksi"}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </div>

      {/* Reorder Confirmation Dialog */}
      <Dialog open={showReorderConfirm} onOpenChange={setShowReorderConfirm}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Konfirmasi Transaksi Ulang</DialogTitle>
          </DialogHeader>
          {foundSale && (
            <div className="space-y-4">
              <div className="bg-gray-50 p-4 rounded-lg">
                <h3 className="font-medium mb-2">Detail Transaksi Sebelumnya:</h3>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-muted-foreground">Nomor:</span>
                    <div className="font-medium">{foundSale.sale_number}</div>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Tanggal:</span>
                    <div className="font-medium">
                      {new Date(foundSale.created_at).toLocaleDateString("id-ID")}
                    </div>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Customer:</span>
                    <div className="font-medium">{foundSale.customer_name || "Walk-in"}</div>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Total:</span>
                    <div className="font-medium">{formatCurrency(foundSale.total_amount)}</div>
                  </div>
                </div>
              </div>

              <div>
                <h4 className="font-medium mb-2">Items yang akan ditambahkan:</h4>
                <div className="max-h-48 overflow-y-auto space-y-2">
                  {foundSale.sale_items?.map((item: any, index: number) => (
                    <div key={index} className="flex justify-between items-center p-2 bg-white border rounded">
                      <div>
                        <div className="font-medium">{item.products?.name}</div>
                        <div className="text-sm text-muted-foreground">
                          {item.quantity} {item.unit_type === 'pcs' ? 'pcs' : (item.products?.base_unit || 'unit')}
                          {item.discount > 0 && (
                            <span className="text-green-600 ml-2">(-{item.discount}%)</span>
                          )}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="font-medium">{formatCurrency(item.subtotal)}</div>
                        <div className="text-sm text-muted-foreground">
                          @ {formatCurrency(item.unit_price)}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="flex justify-end space-x-2 pt-4 border-t">
                <Button 
                  variant="outline" 
                  onClick={() => {
                    setShowReorderConfirm(false);
                    setFoundSale(null);
                  }}
                >
                  Batal
                </Button>
                <Button onClick={handleConfirmReorder}>
                  Konfirmasi Transaksi Ulang
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Products */}
        <Card>
          <CardHeader>
            <CardTitle>Products</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 max-h-96 overflow-y-auto">
              {products?.map((product) => (
                <div
                  key={product.id}
                  className="border rounded-lg p-4 cursor-pointer hover:bg-gray-50"
                  onClick={() => addToCart(product)}
                >
                  <div className="flex items-center justify-between mb-2">
                  <h3 className="font-medium">{product.name}</h3>
                    <div className="text-xs text-muted-foreground">
                      1 {product.base_unit || 'unit'} = {product.pcs_per_base_unit || 1} pcs
                    </div>
                  </div>
                  <p className="text-sm text-muted-foreground">{product.sku}</p>
                  <div className="space-y-1">
                    <p className="font-bold text-lg">
                      {formatCurrency(Number(product.price))} / {product.base_unit || 'unit'}
                    </p>
                    {product.price_per_pcs && Number(product.price_per_pcs) !== Number(product.price) && (
                      <p className="text-sm text-muted-foreground">
                        {formatCurrency(Number(product.price_per_pcs))} / pcs
                      </p>
                    )}
                  </div>
                  {/* Stock Status Indicator */}
                  <div className="mt-2">
                    {Math.floor(product.stock_quantity || 0) < 1 && (product.stock_pcs || 0) > 0 && (
                      <div className="text-xs text-amber-600 bg-amber-50 p-1 rounded">
                        ⚠️ Hanya tersisa {product.stock_pcs} pcs - Tidak bisa jual per {product.base_unit}
                      </div>
                    )}
                  </div>
                  {/* Stock Status Indicator */}
                  <div className="mt-2">
                    {Math.floor(product.stock_quantity || 0) < 1 && (product.stock_pcs || 0) > 0 && (
                      <div className="text-xs text-amber-600 bg-amber-50 p-1 rounded">
                        ⚠️ Hanya tersisa {product.stock_pcs} pcs - Tidak bisa jual per {product.base_unit}
                      </div>
                    )}
                  </div>
                  <Badge
                    variant={
                      (product.stock_pcs || 0) <= (product.min_stock_level || 10)
                        ? "destructive"
                        : "default"
                    }
                  >
                    Stock: {Math.floor(product.stock_quantity * 100) / 100} {product.base_unit || 'units'} ({product.stock_pcs || 0} pcs)
                  </Badge>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Cart & Checkout */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center">
              <ShoppingCart className="h-5 w-5 mr-2" />
              Shopping Cart
              {receiptConfig.discountPercentage > 0 && (
                <Badge variant="secondary" className="ml-2">
                  Global Discount: {receiptConfig.discountPercentage}%
                </Badge>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {cart.length === 0 ? (
              <p className="text-muted-foreground text-center py-8">
                Cart is empty
              </p>
            ) : (
              <>
                <div className="space-y-3 max-h-64 overflow-y-auto">
                  {cart.map((item) => {
                    const itemCalc = calculateDetailedPricing(item);
                    return (
                      <div
                        key={item.product.id}
                        className="border rounded-lg p-3 space-y-2"
                      >
                        <div className="flex items-center justify-between">
                          <div className="flex-1">
                            <h4 className="font-medium">{item.product.name}</h4>
                            <div className="flex items-center space-x-2 mt-1">
                              <Package className="h-3 w-3 text-muted-foreground" />
                              <Select
                                value={item.unitType}
                                onValueChange={(unitType: 'pcs' | 'base_unit') => {
                                  updateItemUnitType(item.product.id, unitType);
                                }}
                              >
                                <SelectTrigger className="h-6 text-xs w-24">
                                  <SelectValue />
                                </SelectTrigger>
                                <SelectContent>
                                  <SelectItem value="pcs">Pcs</SelectItem>
                                  <SelectItem 
                                    value="base_unit"
                                    disabled={Math.floor(item.product.stock_quantity) < 1}
                                  >
                                    {item.product.base_unit || 'Unit'}
                                    {Math.floor(item.product.stock_quantity) < 1 && (
                                      <span className="text-red-500 ml-1">(Tidak Tersedia)</span>
                                    )}
                                  </SelectItem>
                                </SelectContent>
                              </Select>
                              {Math.floor(item.product.stock_quantity) < 1 && (item.product.stock_pcs || 0) > 0 && (
                                <div className="text-xs text-amber-600">
                                  ⚠️ Hanya tersedia satuan
                                </div>
                              )}
                            </div>
                            <p className="text-sm text-muted-foreground">
                              {formatCurrency(
                                item.unitType === 'pcs' 
                                  ? Number(item.product.price_per_pcs || item.product.price)
                                  : Number(item.product.price)
                              )} per {item.unitType === 'pcs' ? 'pcs' : (item.product.base_unit || 'unit')}
                            </p>
                            {item.customDiscount > 0 && (
                              <p className="text-sm text-green-600">
                                Discount: {item.customDiscount}% (-{formatCurrency(itemCalc.discount)})
                              </p>
                            )}
                            <p className="text-sm font-medium">
                              Total: {formatCurrency(itemCalc.finalItemTotal)}
                              {item.unitType === 'base_unit' && item.product.pcs_per_base_unit > 1 && (
                                <span className="text-xs text-muted-foreground ml-1">
                                  (= {item.quantity * (item.product.pcs_per_base_unit || 1)} pcs)
                                </span>
                              )}
                            </p>
                          </div>
                          <div className="flex items-center space-x-1">
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() =>
                                updateQuantity(item.product.id, item.quantity - 1)
                              }
                            >
                              <Minus className="h-3 w-3" />
                            </Button>
                            <span className="w-16 text-center text-sm">
                              {item.quantity} {item.unitType === 'pcs' ? 'pcs' : (item.product.base_unit || 'unit')}
                            </span>
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() =>
                                updateQuantity(item.product.id, item.quantity + 1)
                              }
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

                        {/* Item Discount Input */}
                        <div className="flex items-center space-x-2">
                          <Percent className="h-4 w-4 text-muted-foreground" />
                          <Label htmlFor={`discount-${item.product.id}`} className="text-sm">
                            Item Discount:
                          </Label>
                          <Input
                            id={`discount-${item.product.id}`}
                            type="number"
                            min="0"
                            max="100"
                            step="0.1"
                            value={item.customDiscount}
                            onChange={(e) =>
                              updateItemDiscount(
                                item.product.id,
                                parseFloat(e.target.value) || 0
                              )
                            }
                            className="w-16 h-8 text-sm"
                          />
                          <span className="text-sm text-muted-foreground">%</span>
                        </div>
                      </div>
                    );
                  })}
                </div>

                <div className="space-y-2 border-t pt-4">
                  <div className="flex justify-between text-sm">
                    <span>Subtotal:</span>
                    <span>{formatCurrency(subtotal)}</span>
                  </div>
                  {cart.some(item => item.customDiscount > 0) && (
                    <div className="flex justify-between text-sm text-green-600">
                      <span>Total Discount:</span>
                      <span>-{formatCurrency(cart.reduce((sum, item) => sum + calculateDetailedPricing(item).discount, 0))}</span>
                    </div>
                  )}
                  <div className="flex justify-between font-bold text-lg">
                    <span>Total:</span>
                    <span>{formatCurrency(total)}</span>
                  </div>
                </div>

                <div className="space-y-4 border-t pt-4">
                  <div>
                    <Label htmlFor="customerName">
                      Customer Name (Optional)
                    </Label>
                    <Input
                      id="customerName"
                      value={customerName}
                      onChange={(e) => setCustomerName(e.target.value)}
                      placeholder="Enter customer name"
                    />
                  </div>

                  <div>
                    <Label htmlFor="salesName">Nama Sales</Label>
                    <Input
                      id="salesName"
                      value={selectedCashier}
                      onChange={(e) => setSelectedCashier(e.target.value)}
                      placeholder="Masukkan nama sales"
                    />
                  </div>

                  <div>
                    <Label htmlFor="paymentMethod">Payment Method</Label>
                    <Select
                      value={paymentMethod}
                      onValueChange={setPaymentMethod}
                    >
                      <SelectTrigger>
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="cash">Cash</SelectItem>
                        <SelectItem value="card">Card</SelectItem>
                        <SelectItem value="transfer">Transfer</SelectItem>
                        <SelectItem value="credit">Credit</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  {paymentMethod !== "cash" && (
                    <div className="space-y-2">
                      <Label htmlFor="bankDetails">Bank Details</Label>
                      <Input
                        id="bankDetails"
                        value={bankDetails}
                        onChange={(e) => setBankDetails(e.target.value)}
                        placeholder="Enter bank name, account number, etc."
                      />
                    </div>
                  )}

                  <div>
                    <Label htmlFor="paymentReceived">Payment Received</Label>
                    <Input
                      id="paymentReceived"
                      type="number"
                      step="0.01"
                      value={paymentReceived}
                      onChange={(e) =>
                        setPaymentReceived(parseFloat(e.target.value) || 0)
                      }
                      placeholder="Enter payment amount"
                    />
                    {paymentMethod !== "cash" && (
                      <p className="text-sm text-muted-foreground mt-1">
                        Auto-filled with total amount for non-cash payments
                      </p>
                    )}
                  </div>

                  {paymentReceived > 0 && (
                    <div className="flex justify-between text-lg">
                      <span>Change:</span>
                      <span
                        className={
                          change < 0 ? "text-red-600" : "text-green-600"
                        }
                      >
                        {formatCurrency(Math.max(0, change))}
                      </span>
                      {change < 0 && (
                        <span className="text-red-600 text-sm">Insufficient payment</span>
                      )}
                    </div>
                  )}

                  <div className="space-y-2">
                    <Button
                      className="w-full"
                      variant="outline"
                      onClick={() => setShowPreCheckout(true)}
                      disabled={cart.length === 0}
                    >
                      <Calculator className="h-4 w-4 mr-2" />
                      Discount Options (Optional)
                    </Button>

                    <Button
                      className="w-full"
                      onClick={() => processSaleMutation.mutate()}
                      disabled={
                        cart.length === 0 ||
                        (paymentMethod === "cash" && paymentReceived < total) ||
                        processSaleMutation.isPending
                      }
                    >
                      <Receipt className="h-4 w-4 mr-2" />
                      {processSaleMutation.isPending
                        ? "Processing..."
                        : "Complete Sale"}
                    </Button>
                  </div>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>

      <PreCheckoutDialog
        open={showPreCheckout}
        onOpenChange={setShowPreCheckout}
        cart={cart}
        onCartUpdate={setCart}
        onProceedToPayment={handlePreCheckoutProceed}
      />
      
      {/* Confirm Reorder Dialog */}
      <Dialog open={isConfirmReorderOpen} onOpenChange={setIsConfirmReorderOpen}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Konfirmasi Transaksi Ulang</DialogTitle>
          </DialogHeader>
          
          {foundSale && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4 p-4 bg-gray-50 rounded-lg">
                <div>
                  <Label className="text-sm font-medium">Nomor Penjualan:</Label>
                  <p className="font-mono">{foundSale.sale_number}</p>
                </div>
                <div>
                  <Label className="text-sm font-medium">Customer:</Label>
                  <p>{foundSale.customer_name || 'Walk-in Customer'}</p>
                </div>
                <div>
                  <Label className="text-sm font-medium">Tanggal:</Label>
                  <p>{new Date(foundSale.created_at).toLocaleDateString('id-ID')}</p>
                </div>
                <div>
                  <Label className="text-sm font-medium">Total:</Label>
                  <p className="font-bold text-green-600">
                    {formatCurrency(Number(foundSale.total_amount))}
                  </p>
                </div>
              </div>
              
              <div>
                <Label className="text-sm font-medium mb-2 block">Item Transaksi:</Label>
                <div className="border rounded-lg">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Produk</TableHead>
                        <TableHead>Qty</TableHead>
                        <TableHead>Harga</TableHead>
                        <TableHead>Discount</TableHead>
                        <TableHead>Subtotal</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {foundSale.sale_items?.map((item: any, index: number) => (
                        <TableRow key={index}>
                          <TableCell>{item.products?.name || 'Unknown Product'}</TableCell>
                          <TableCell>{item.quantity}</TableCell>
                          <TableCell>{formatCurrency(Number(item.unit_price))}</TableCell>
                          <TableCell>{item.discount || 0}%</TableCell>
                          <TableCell>{formatCurrency(Number(item.subtotal))}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </div>
              
              <div className="bg-blue-50 p-4 rounded-lg">
                <p className="text-sm text-blue-800">
                  <strong>Perhatian:</strong> Transaksi ini akan disalin ke keranjang belanja. 
                  Keranjang saat ini akan dikosongkan dan diganti dengan item dari transaksi yang dipilih.
                </p>
              </div>
            </div>
          )}
          
          <DialogFooter>
            <Button 
              variant="outline" 
              onClick={() => {
                setIsConfirmReorderOpen(false);
                setFoundSale(null);
                setSearchSaleNumber('');
              }}
            >
              Batal
            </Button>
            <Button onClick={handleConfirmReorder}>
              Ya, Buat Transaksi Ulang
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Cashier;