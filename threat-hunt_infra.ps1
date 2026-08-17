# Variables
$vnetName = "Production_VNET"
$vmName = "JumpostSvr"
$location = "CentralUS"
$resourceGroup = "technical_ops"
$subnetName = "Subnet1"
$nsgName = "RMONSG"
$publicIpName = "RMOPublicIP"
$nicName = "RMONIC"

# Credentials
$username = "rmoadmin"
$password = Read-Host "Enter password" -AsSecureString
$cred = New-Object System.Management.Automation.PSCredential ($username, $password)

# Ensure Resource Group exists
$rg = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Output "Creating Resource Group..."
    $rg = New-AzResourceGroup -Name $resourceGroup -Location $location
}

# Get or Create VNet
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue

if (-not $vnet) {
    Write-Output "Creating VNet..."
    $vnet = New-AzVirtualNetwork `
        -ResourceGroupName $resourceGroup `
        -Location $location `
        -Name $vnetName `
        -AddressPrefix "10.0.0.0/16"
}

if (-not $vnet) { throw "VNet failed." }

# Get or Create Subnet
$subnet = Get-AzVirtualNetworkSubnetConfig `
    -Name $subnetName `
    -VirtualNetwork $vnet `
    -ErrorAction SilentlyContinue

if (-not $subnet) {
    Write-Output "Creating Subnet..."

    $updatedVnet = Add-AzVirtualNetworkSubnetConfig `
        -Name $subnetName `
        -VirtualNetwork $vnet `
        -AddressPrefix "10.0.1.0/24"

    if (-not $updatedVnet) { throw "Subnet add failed." }

    $vnet = Set-AzVirtualNetwork -VirtualNetwork $updatedVnet
    if (-not $vnet) { throw "VNet update failed." }

    $subnet = Get-AzVirtualNetworkSubnetConfig `
        -Name $subnetName `
        -VirtualNetwork $vnet
}

# Get or Create NSG
$nsg = Get-AzNetworkSecurityGroup `
    -Name $nsgName `
    -ResourceGroupName $resourceGroup `
    -ErrorAction SilentlyContinue

if (-not $nsg) {
    Write-Output "Creating NSG..."

    $nsg = New-AzNetworkSecurityGroup `
        -ResourceGroupName $resourceGroup `
        -Location $location `
        -Name $nsgName
}

if (-not $nsg) { throw "NSG failed." }

# Add NSG Rules (only if missing)
$rules = $nsg.SecurityRules.Name

if ($rules -notcontains "Allow-HTTP") {
    $nsg = Add-AzNetworkSecurityRuleConfig `
        -Name "Allow-HTTP" `
        -NetworkSecurityGroup $nsg `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 1011 `
        -SourceAddressPrefix * `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange 80 `
        -Access Allow
}

if ($rules -notcontains "Allow-HTTPS") {
    $nsg = Add-AzNetworkSecurityRuleConfig `
        -Name "Allow-HTTPS" `
        -NetworkSecurityGroup $nsg `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 1021 `
        -SourceAddressPrefix * `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange 443 `
        -Access Allow
}

# Commit NSG
$nsg = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg

# Create Public IP
$publicIp = New-AzPublicIpAddress `
    -ResourceGroupName $resourceGroup `
    -Location $location `
    -Name $publicIpName `
    -AllocationMethod Static `
    -Sku Standard

# Get or Create NIC
$nic = Get-AzNetworkInterface `
    -Name $nicName `
    -ResourceGroupName $resourceGroup `
    -ErrorAction SilentlyContinue

if (-not $nic) {
    Write-Output "Creating NIC..."

    $nic = New-AzNetworkInterface `
        -Name $nicName `
        -ResourceGroupName $resourceGroup `
        -Location $location `
        -SubnetId $subnet.Id `
        -PublicIpAddressId $publicIp.Id `
        -NetworkSecurityGroupId $nsg.Id
}

if (-not $nic) { throw "NIC failed." }

# Check if VM exists
$vm = Get-AzVM -Name $vmName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue

if (-not $vm) {
    Write-Output "Creating VM..."

    $vmConfig = New-AzVMConfig `
        -VMName $vmName `
        -VMSize "Standard_D4_v5"

    $vmConfig = Set-AzVMOperatingSystem `
        -VM $vmConfig `
        -Windows `
        -ComputerName $vmName `
        -Credential $cred `
        -ProvisionVMAgent `
        -EnableAutoUpdate

    $vmConfig = Set-AzVMSourceImage `
        -VM $vmConfig `
        -PublisherName "MicrosoftWindowsServer" `
        -Offer "WindowsServer" `
        -Skus "2025-datacenter" `
        -Version "latest"

    $vmConfig = Add-AzVMNetworkInterface `
        -VM $vmConfig `
        -Id $nic.Id

    $vmConfig = Set-AzVMOSDisk `
        -VM $vmConfig `
        -Name "$vmName-OSDisk" `
        -CreateOption FromImage `
        -DiskSizeInGB 250 `
        -StorageAccountType "Standard_LRS"

    New-AzVM `
        -ResourceGroupName $resourceGroup `
        -Location $location `
        -VM $vmConfig
}
else {
    Write-Output "VM already exists. Skipping creation."
}

Write-Output "Deployment complete"