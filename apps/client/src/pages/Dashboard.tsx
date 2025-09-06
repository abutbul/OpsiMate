import { useState, useMemo, useRef, useEffect, useCallback } from "react"
import { useNavigate } from "react-router-dom"
import { useToast } from "@/hooks/use-toast"
import { ServiceTable, Service } from "@/components/ServiceTable"
import { RightSidebarWithLogs as RightSidebar } from "@/components/RightSidebarWithLogs"
import { ActionButtons } from "@/components/ActionButtons"
import { TableSettingsModal } from "@/components/TableSettingsModal"
import { AddServiceModal } from "@/components/AddServiceModal"
import { FilterPanel, Filters } from "@/components/FilterPanel"
import { SavedViewsManager } from "@/components/SavedViewsManager"
import { DashboardLayout } from "../components/DashboardLayout"
import { SavedView } from "@/types/SavedView"
import { useServices, useAlerts, useStartService, useStopService, useDismissAlert, useSaveView, useDeleteView, useViews, useActiveView } from "@/hooks/queries"
import { Alert } from "@OpsiMate/shared"
import { TVModeLauncher } from "@/components/TVModeLauncher"
import { Button } from "@/components/ui/button"
import { ChevronLeft, ChevronRight } from "lucide-react"
import { cn } from "@/lib/utils"


const Dashboard = () => {
    const navigate = useNavigate()
    const {toast} = useToast()
    
    // React Query hooks for data fetching
    const { data: services = [], isLoading: servicesLoading, error: servicesError } = useServices();
    const { data: alerts = [], error: alertsError } = useAlerts();
    const { data: savedViews = [], error: viewsError } = useViews();
    const { activeViewId, setActiveView, error: activeViewError } = useActiveView();
    
    // Mutations
    const startServiceMutation = useStartService();
    const stopServiceMutation = useStopService();
    const dismissAlertMutation = useDismissAlert();
    const saveViewMutation = useSaveView();
    const deleteViewMutation = useDeleteView();
    
    const [selectedService, setSelectedService] = useState<Service | null>(null)
    const [selectedServices, setSelectedServices] = useState<Service[]>([])
    const [showTableSettings, setShowTableSettings] = useState(false)
    const [showAddService, setShowAddService] = useState(false)
    const [visibleColumns, setVisibleColumns] = useState({
        name: true,
        serviceIP: true,
        serviceStatus: true,
        provider: true,
        containerDetails: false,
        tags: true,
        alerts: true
    })
    const [filters, setFilters] = useState<Filters>({})
    const [filterPanelCollapsed, setFilterPanelCollapsed] = useState(false)
    const [rightSidebarCollapsed, setRightSidebarCollapsed] = useState(false)
    const [searchTerm, setSearchTerm] = useState("")
    const [columnOrder, setColumnOrder] = useState<string[]>(['name', 'serviceIP', 'serviceStatus', 'provider', 'containerDetails', 'tags', 'alerts'])

    // Enhanced alert calculation: each service gets alerts for ALL its tags
    const servicesWithAlerts = useMemo(() => {
        console.log('Debug - Services:', services.length, 'Alerts:', alerts.length)
        return services.map(service => {
            console.log(`Service ${service.name} tags:`, service.tags?.map(t => t.name) || [])
            
            // Get all unique alerts that match any of the service's tags (including dismissed)
            const serviceAlerts = alerts.filter(alert => {
                console.log(`Checking alert ${alert.id} (tag: ${alert.tag}) against service ${service.name}`)
                
                // Check if alert tag matches any of the service's tags
                const matches = service.tags?.some(tag => tag.name === alert.tag)
                console.log(`Match result: ${matches}`)
                return matches
            })
            
            // Remove duplicates (in case an alert matches multiple tags of the same service)
            const uniqueAlerts = serviceAlerts.filter((alert, index, self) => 
                index === self.findIndex(a => a.id === alert.id)
            )
            
            // Count only non-dismissed alerts for the badge count
            const activeAlerts = uniqueAlerts.filter(alert => !alert.isDismissed);
            
            console.log(`Service ${service.name} final result: ${activeAlerts.length} active, ${uniqueAlerts.length - activeAlerts.length} dismissed`)
            
            return {
                ...service,
                alertsCount: activeAlerts.length, // Only count non-dismissed alerts
                serviceAlerts: uniqueAlerts // Store ALL alerts for sidebar display (including dismissed)
            }
        })
    }, [services, alerts])

    // Update selectedService when servicesWithAlerts changes
    useEffect(() => {
        if (selectedService) {
            const updatedService = servicesWithAlerts.find(s => s.id === selectedService.id)
            if (updatedService) {
                setSelectedService(updatedService)
            }
        }
    }, [servicesWithAlerts, selectedService])

    // Load saved views and active view on component mount
    useEffect(() => {
        const loadViews = async () => {
            try {
                if (activeViewId) {
                    const activeView = savedViews.find(view => view.id === activeViewId);
                    if (activeView) {
                        applyView(activeView);
                    } else if (activeViewId === 'default-view') {
                        // If the active view is 'default-view' but it doesn't exist, create a default state
                        // Apply default filters and settings
                        setFilters({});
                        setSearchTerm('');
                        setVisibleColumns({
                            name: true,
                            serviceIP: true,
                            serviceStatus: true,
                            provider: true,
                            containerDetails: true,
                            tags: true,
                            alerts: true
                        });
                    } else {
                        // If the active view ID doesn't exist, fall back to the first available view or default
                        const firstView = savedViews[0];
                        if (firstView) {
                            setActiveView(firstView.id);
                            applyView(firstView);
                        } else {
                            setActiveView('default-view');
                        }
                    }
                }
            } catch (error) {
                console.error('Error loading saved views:', error);
                toast({
                    title: "Error",
                    description: "Failed to load saved views",
                    variant: "destructive"
                });
            }
        };

        if (savedViews.length > 0 && activeViewId) {
            loadViews();
        }
    }, [savedViews, activeViewId, setActiveView, toast]);

    // Handle errors from React Query
    useEffect(() => {
        if (servicesError) {
            toast({
                title: "Error loading services",
                description: servicesError.message || "Failed to load services",
                variant: "destructive"
            });
        }
    }, [servicesError, toast]);

    useEffect(() => {
        if (viewsError) {
            toast({
                title: "Error loading views",
                description: "Failed to load saved views",
                variant: "destructive"
            });
        }
    }, [viewsError, toast]);

    const filteredServices = useMemo(() => {
        const activeFilterKeys = Object.keys(filters).filter(key => filters[key].length > 0);
        if (activeFilterKeys.length === 0) {
            return servicesWithAlerts;
        }

        return servicesWithAlerts.filter(service => {
            return activeFilterKeys.every(key => {
                const filterValues = filters[key];
                if (Array.isArray(filterValues) && filterValues.length > 0) {
                    // Handle different filter field types
                    switch (key) {
                        case 'serviceStatus':
                        case 'serviceType':
                            // Direct service properties
                            return filterValues.includes(String(service[key]));
                        
                        case 'providerType':
                            // Nested provider property
                            return filterValues.includes(String(service.provider?.providerType));
                        
                        case 'providerName':
                            // Nested provider property
                            return filterValues.includes(String(service.provider?.name));
                        
                        case 'containerNamespace':
                            // Nested container details property
                            return filterValues.includes(String(service.containerDetails?.namespace));
                        
                        case 'tags':
                            // Handle tags array - service must have ALL selected tags (AND logic)
                            if (!service.tags || service.tags.length === 0) {
                                return false;
                            }
                            // Check if the service has ALL the selected tags
                            return filterValues.every(selectedTag => 
                                service.tags.some(tag => tag.name === selectedTag)
                            );
                        
                        default:
                            // Fallback for any other direct properties
                            return filterValues.includes(String(service[key as keyof Service]));
                    }
                }
                return true;
            });
        });
    }, [servicesWithAlerts, filters]);

    const toggleFilterPanel = () => {
        setFilterPanelCollapsed(!filterPanelCollapsed)
    }

    const handleSaveView = async (view: SavedView) => {
        try {
            await saveViewMutation.mutateAsync(view);
            await setActiveView(view.id);
            return Promise.resolve();
        } catch (error) {
            console.error('Error saving view:', error);
            return Promise.reject(error);
        }
    }

    const handleDeleteView = async (viewId: string) => {
        try {
            await deleteViewMutation.mutateAsync(viewId);

            if (activeViewId === viewId) {
                await setActiveView(undefined);
            }

            toast({
                title: "View Deleted",
                description: "The saved view has been deleted."
            });
        } catch (error) {
            console.error('Error deleting view:', error);
            toast({
                title: "Error",
                description: "Failed to delete view",
                variant: "destructive"
            });
        }
    }

    const applyView = async (view: SavedView) => {
        try {
            setFilters(view.filters);
            // Ensure visibleColumns has all required properties
            setVisibleColumns(prev => ({
                ...prev,
                ...view.visibleColumns
            }));
            setSearchTerm(view.searchTerm);
            await setActiveView(view.id);

            // Only show toast if not the default 'All Services' view
            if (view.name !== "All Services") {
                toast({
                    title: "View Applied",
                    description: `"${view.name}" view has been applied.`
                });
            }
        } catch (error) {
            console.error('Error applying view:', error);
            toast({
                title: "Error",
                description: "Failed to apply view",
                variant: "destructive"
            });
        }
    }

    const handleShowServices = () => {
        toast({
            title: "Services Loaded",
            description: `Loaded ${services.length} services from your infrastructure.`
        })
    }

    const handleAddService = (serviceData: any) => {
        toast({
            title: "Service Added",
            description: `${serviceData.name} has been added successfully.`
        })
    }

    const handleServicesSelect = (services: Service[]) => {
        setSelectedServices(services)
        if (services.length === 1) {
            // Find the service with alerts from servicesWithAlerts
            const serviceWithAlerts = servicesWithAlerts.find(s => s.id === services[0].id)
            setSelectedService(serviceWithAlerts || services[0])
        } else {
            setSelectedService(null)
        }
    }

    const handleColumnToggle = (column: string) => {
        setVisibleColumns(prev => ({
            ...prev,
            [column]: !prev[column]
        }));
    };

    const handleServiceUpdate = (updatedService: Service) => {
        if (selectedService && selectedService.id === updatedService.id) {
            setSelectedService(updatedService);
        }
    };

    const handleStart = async () => {
        if (selectedServices.length > 0) {
            toast({
                title: "Starting Services",
                description: `Starting ${selectedServices.length} service${selectedServices.length !== 1 ? 's' : ''}...`
            })

            // Track success and failures
            let successCount = 0;
            let failureCount = 0;

            // Process each service
            for (const service of selectedServices) {
                try {
                    const serviceId = parseInt(service.id);
                    await startServiceMutation.mutateAsync(serviceId);
                    successCount++;
                } catch (error) {
                    failureCount++;
                    console.error(`Error starting service ${service.name}:`, error);
                }
            }

            // Show result toast
            if (successCount > 0 && failureCount === 0) {
                toast({
                    title: "Services Started",
                    description: `Successfully started ${successCount} service${successCount !== 1 ? 's' : ''}.`
                });
            } else if (successCount > 0 && failureCount > 0) {
                toast({
                    title: "Partial Success",
                    description: `Started ${successCount} service${successCount !== 1 ? 's' : ''}, but ${failureCount} failed.`,
                    variant: "default"
                });
            } else {
                toast({
                    title: "Failed to Start Services",
                    description: `All ${failureCount} service${failureCount !== 1 ? 's' : ''} failed to start.`,
                    variant: "destructive"
                });
            }
        }
    }

    const handleStop = async () => {
        if (selectedServices.length > 0) {
            toast({
                title: "Stopping Services",
                description: `Stopping ${selectedServices.length} service${selectedServices.length !== 1 ? 's' : ''}...`
            })

            // Track success and failures
            let successCount = 0;
            let failureCount = 0;

            // Process each service
            for (const service of selectedServices) {
                try {
                    const serviceId = parseInt(service.id);
                    await stopServiceMutation.mutateAsync(serviceId);
                    successCount++;
                } catch (error) {
                    failureCount++;
                    console.error(`Error stopping service ${service.name}:`, error);
                }
            }

            // Show result toast
            if (successCount > 0 && failureCount === 0) {
                toast({
                    title: "Services Stopped",
                    description: `Successfully stopped ${successCount} service${successCount !== 1 ? 's' : ''}.`
                });
            } else if (successCount > 0 && failureCount > 0) {
                toast({
                    title: "Partial Success",
                    description: `Stopped ${successCount} service${successCount !== 1 ? 's' : ''}, but ${failureCount} failed.`,
                    variant: "default"
                });
            } else {
                toast({
                    title: "Failed to Stop Services",
                    description: `All ${failureCount} service${failureCount !== 1 ? 's' : ''} failed to stop.`,
                    variant: "destructive"
                });
            }
        }
    }

    const handleRestart = async () => {
        if (selectedServices.length > 0) {
            toast({
                title: "Restarting Services",
                description: `Restarting ${selectedServices.length} service${selectedServices.length !== 1 ? 's' : ''}...`
            })

            // Track success and failures
            let successCount = 0;
            let failureCount = 0;

            // Process each service - first stop, then start
            for (const service of selectedServices) {
                try {
                    const serviceId = parseInt(service.id);

                    // First stop the service
                    await stopServiceMutation.mutateAsync(serviceId);
                    
                    // Then start the service
                    await startServiceMutation.mutateAsync(serviceId);
                    successCount++;
                } catch (error) {
                    failureCount++;
                    console.error(`Error restarting service ${service.name}:`, error);
                }
            }

            // Show result toast
            if (successCount > 0 && failureCount === 0) {
                toast({
                    title: "Services Restarted",
                    description: `Successfully restarted ${successCount} service${successCount !== 1 ? 's' : ''}.`
                });
            } else if (successCount > 0 && failureCount > 0) {
                toast({
                    title: "Partial Success",
                    description: `Restarted ${successCount} service${successCount !== 1 ? 's' : ''}, but ${failureCount} failed.`,
                    variant: "default"
                });
            } else {
                toast({
                    title: "Failed to Restart Services",
                    description: `All ${failureCount} service${failureCount !== 1 ? 's' : ''} failed to restart.`,
                    variant: "destructive"
                });
            }
        }
    }



    const handleAlertDismiss = async (alertId: string) => {
        try {
            await dismissAlertMutation.mutateAsync(alertId);
        } catch (error) {
            console.error('Error dismissing alert:', error);
            toast({
                title: "Error",
                description: "Failed to dismiss alert",
                variant: "destructive"
            });
        }
    }

    return (
        <div className="flex flex-col h-screen">
            <DashboardLayout>
                <div className="flex flex-col h-full">
                    <div className="flex flex-row h-full">
                        <div className={cn(
                            "border-r border-border transition-all duration-300 ease-in-out flex-shrink-0 relative",
                            filterPanelCollapsed ? "w-12" : "w-48"
                        )}>
                            <div className="h-full flex flex-col">
                                <div className="flex items-center justify-between p-2 border-b border-border">
                                    {!filterPanelCollapsed && (
                                        <h3 className="text-sm font-semibold text-foreground">Filters</h3>
                                    )}
                                </div>
                                <div className="flex-1 overflow-hidden">
                                    <FilterPanel
                                        services={services}
                                        filters={filters}
                                        onFilterChange={setFilters}
                                        collapsed={filterPanelCollapsed}
                                    />
                                </div>
                            </div>
                            <Button
                                onClick={toggleFilterPanel}
                                variant="ghost"
                                size="icon"
                                className="z-10 absolute top-1/2 -right-4 -translate-y-1/2 border bg-background hover:bg-muted rounded-full h-8 w-8"
                                title={filterPanelCollapsed ? "Expand filters" : "Collapse filters"}
                            >
                                {filterPanelCollapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}
                            </Button>
                        </div>
                        <div className="flex-1 flex flex-col">
                            <div className="flex-1 p-2 flex flex-col overflow-auto">
                                <div className="flex justify-between items-center mb-2">
                                    <SavedViewsManager
                                        currentFilters={filters}
                                        currentVisibleColumns={visibleColumns}
                                        currentSearchTerm={searchTerm}
                                        savedViews={savedViews}
                                        onSaveView={handleSaveView}
                                        onDeleteView={handleDeleteView}
                                        onLoadView={applyView}
                                        activeViewId={activeViewId}
                                    />
                                    <TVModeLauncher 
                                        currentFilters={filters}
                                        currentVisibleColumns={visibleColumns}
                                        currentSearchTerm={searchTerm}
                                        activeViewId={activeViewId}
                                    />
                                </div>
                                <ServiceTable
                                    services={filteredServices}
                                    selectedServices={selectedServices}
                                    onServicesSelect={handleServicesSelect}
                                    onSettingsClick={() => setShowTableSettings(true)}
                                    visibleColumns={visibleColumns}
                                    searchTerm={searchTerm}
                                    onSearchChange={setSearchTerm}
                                    loading={servicesLoading}
                                    columnOrder={columnOrder}
                                    onColumnOrderChange={setColumnOrder}
                                />
                            </div>
                            <div className="flex-shrink-0 p-2 border-t border-border">
                                <ActionButtons
                                    selectedService={selectedService}
                                    selectedServices={selectedServices}
                                    onStart={handleStart}
                                    onStop={handleStop}
                                    onRestart={handleRestart}
                                />
                            </div>
                        </div>
                        {selectedServices.length === 1 && selectedService && (
                            <div className="w-80 border-l border-border">
                                <RightSidebar
                                    service={selectedService}
                                    onClose={() => setSelectedService(null)}
                                    collapsed={rightSidebarCollapsed}
                                    onServiceUpdate={handleServiceUpdate}
                                    alerts={alerts}
                                    onAlertDismiss={handleAlertDismiss}
                                />
                            </div>
                        )}
                    </div>
                </div>
            </DashboardLayout>

            <TableSettingsModal
                open={showTableSettings}
                onOpenChange={setShowTableSettings}
                visibleColumns={visibleColumns}
                onColumnToggle={handleColumnToggle}
            />

            <AddServiceModal
                open={showAddService}
                onOpenChange={setShowAddService}
                onAddService={handleAddService}
            />
        </div>
    )
}

export default Dashboard;