import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Plus, Edit, Trash2, Package } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { Switch } from '@/components/ui/switch';

interface ProductUnitsManagerProps {
  productId: string;
  productName: string;
}

const ProductUnitsManager = ({ productId, productName }: ProductUnitsManagerProps) => {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [editingUnit, setEditingUnit] = useState<any>(null);

  const { data: units, isLoading } = useQuery({
    queryKey: ['product-units', productId],
    queryFn: async () => {
      const { data } = await supabase
        .from('product_units')
        .select('*')
        .eq('product_id', productId)
        .eq('is_active', true)
        .order('is_base_unit', { ascending: false });
      return data || [];
    },
  });

  const createUnitMutation = useMutation({
    mutationFn: async (unitData: any) => {
      const { error } = await supabase.from('product_units').insert([{
        ...unitData,
        product_id: productId
      }]);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['product-units', productId] });
      setIsDialogOpen(false);
      setEditingUnit(null);
      toast({ title: "Success", description: "Unit created successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const updateUnitMutation = useMutation({
    mutationFn: async ({ id, ...unitData }: any) => {
      const { error } = await supabase
        .from('product_units')
        .update(unitData)
        .eq('id', id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['product-units', productId] });
      setIsDialogOpen(false);
      setEditingUnit(null);
      toast({ title: "Success", description: "Unit updated successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const deleteUnitMutation = useMutation({
    mutationFn: async (unitId: string) => {
      const { error } = await supabase
        .from('product_units')
        .update({ is_active: false })
        .eq('id', unitId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['product-units', productId] });
      toast({ title: "Success", description: "Unit deleted successfully" });
    },
    onError: (error: any) => {
      toast({ title: "Error", description: error.message, variant: "destructive" });
    },
  });

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    
    const unitData = {
      unit_name: formData.get('unit_name') as string,
      conversion_factor: parseFloat(formData.get('conversion_factor') as string),
      is_base_unit: formData.get('is_base_unit') === 'on',
    };

    if (editingUnit) {
      updateUnitMutation.mutate({ id: editingUnit.id, ...unitData });
    } else {
      createUnitMutation.mutate(unitData);
    }
  };

  const commonUnits = [
    { name: 'pcs', label: 'Pieces' },
    { name: 'dus', label: 'Dus/Box' },
    { name: 'lusin', label: 'Lusin (12 pcs)' },
    { name: 'kodi', label: 'Kodi (20 pcs)' },
    { name: 'gross', label: 'Gross (144 pcs)' },
    { name: 'kg', label: 'Kilogram' },
    { name: 'gram', label: 'Gram' },
    { name: 'liter', label: 'Liter' },
    { name: 'ml', label: 'Mililiter' },
    { name: 'meter', label: 'Meter' },
    { name: 'cm', label: 'Centimeter' },
  ];

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h3 className="text-lg font-semibold">Units for {productName}</h3>
        <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
          <DialogTrigger asChild>
            <Button size="sm" onClick={() => setEditingUnit(null)}>
              <Plus className="h-4 w-4 mr-2" />
              Add Unit
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>
                {editingUnit ? 'Edit Unit' : 'Add New Unit'}
              </DialogTitle>
            </DialogHeader>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <Label htmlFor="unit_name">Unit Name</Label>
                <Input
                  id="unit_name"
                  name="unit_name"
                  defaultValue={editingUnit?.unit_name}
                  placeholder="e.g., pcs, dus, kg"
                  required
                />
                <div className="mt-2">
                  <Label className="text-sm text-muted-foreground">Common units:</Label>
                  <div className="flex flex-wrap gap-1 mt-1">
                    {commonUnits.map((unit) => (
                      <Button
                        key={unit.name}
                        type="button"
                        variant="outline"
                        size="sm"
                        className="h-6 text-xs"
                        onClick={() => {
                          const input = document.getElementById('unit_name') as HTMLInputElement;
                          if (input) input.value = unit.name;
                        }}
                      >
                        {unit.name}
                      </Button>
                    ))}
                  </div>
                </div>
              </div>
              
              <div>
                <Label htmlFor="conversion_factor">Conversion Factor</Label>
                <Input
                  id="conversion_factor"
                  name="conversion_factor"
                  type="number"
                  step="0.0001"
                  min="0.0001"
                  defaultValue={editingUnit?.conversion_factor || 1}
                  required
                />
                <p className="text-sm text-muted-foreground mt-1">
                  How many base units equal 1 of this unit? (e.g., 1 dus = 12 pcs, so conversion factor = 12)
                </p>
              </div>

              <div className="flex items-center space-x-2">
                <Switch
                  id="is_base_unit"
                  name="is_base_unit"
                  defaultChecked={editingUnit?.is_base_unit || false}
                />
                <Label htmlFor="is_base_unit">Set as base unit</Label>
              </div>

              <div className="flex justify-end space-x-2">
                <Button type="button" variant="outline" onClick={() => setIsDialogOpen(false)}>
                  Cancel
                </Button>
                <Button type="submit" disabled={createUnitMutation.isPending || updateUnitMutation.isPending}>
                  {editingUnit ? 'Update' : 'Create'} Unit
                </Button>
              </div>
            </form>
          </DialogContent>
        </Dialog>
      </div>

      {isLoading ? (
        <div>Loading units...</div>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Unit Name</TableHead>
              <TableHead>Conversion Factor</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {units?.map((unit) => (
              <TableRow key={unit.id}>
                <TableCell className="font-medium">{unit.unit_name}</TableCell>
                <TableCell>
                  {unit.is_base_unit ? '1 (Base)' : `${unit.conversion_factor}`}
                </TableCell>
                <TableCell>
                  {unit.is_base_unit ? (
                    <Badge variant="default">Base Unit</Badge>
                  ) : (
                    <Badge variant="secondary">Conversion Unit</Badge>
                  )}
                </TableCell>
                <TableCell>
                  <div className="flex items-center space-x-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => {
                        setEditingUnit(unit);
                        setIsDialogOpen(true);
                      }}
                    >
                      <Edit className="h-4 w-4" />
                    </Button>
                    {!unit.is_base_unit && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => deleteUnitMutation.mutate(unit.id)}
                        className="text-red-600 hover:text-red-700"
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {units && units.length > 0 && (
        <div className="mt-4 p-4 bg-gray-50 rounded-lg">
          <h4 className="font-medium mb-2">Unit Conversion Examples:</h4>
          <div className="text-sm space-y-1">
            {units.map((unit) => (
              <div key={unit.id}>
                1 {unit.unit_name} = {unit.conversion_factor} {units.find(u => u.is_base_unit)?.unit_name || 'base units'}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

export default ProductUnitsManager;