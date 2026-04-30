function Normalize-WacCertificateThumbprint {
  param(
    [AllowNull()][string]$Thumbprint = ""
  )

  if ([string]::IsNullOrWhiteSpace($Thumbprint)) { return "" }

  return ([regex]::Replace($Thumbprint, "[^0-9A-Fa-f]", "")).ToUpperInvariant()
}

function New-WacValidationResult {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("OK", "WARN", "RISK", "BLOCKED")]
    [string]$Level,

    [Parameter(Mandatory = $true)]
    [string]$Code,

    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  return [pscustomobject]@{
    Level = $Level
    Code = $Code
    Message = $Message
  }
}

function Test-WacPortPlan {
  param(
    [int]$Port,
    [int]$ServicePortStart,
    [int]$ServicePortEnd
  )

  if (($Port -lt 1) -or ($Port -gt 65535)) {
    return New-WacValidationResult -Level "BLOCKED" -Code "WacPortOutOfRange" -Message "WAC port must be between 1 and 65535."
  }

  if (($ServicePortStart -lt 1) -or ($ServicePortStart -gt 65535)) {
    return New-WacValidationResult -Level "BLOCKED" -Code "ServicePortStartOutOfRange" -Message "Service port start must be between 1 and 65535."
  }

  if (($ServicePortEnd -lt 1) -or ($ServicePortEnd -gt 65535)) {
    return New-WacValidationResult -Level "BLOCKED" -Code "ServicePortEndOutOfRange" -Message "Service port end must be between 1 and 65535."
  }

  if ($ServicePortStart -gt $ServicePortEnd) {
    return New-WacValidationResult -Level "BLOCKED" -Code "ServicePortRangeReversed" -Message "Service port start must be less than or equal to service port end."
  }

  if (($Port -ge $ServicePortStart) -and ($Port -le $ServicePortEnd)) {
    return New-WacValidationResult -Level "BLOCKED" -Code "WacPortOverlapsServiceRange" -Message "WAC port must not be inside the service port range."
  }

  if ($Port -lt 1024) {
    return New-WacValidationResult -Level "WARN" -Code "WacPortPrivileged" -Message "WAC port is below 1024 and may require elevated privileges."
  }

  return New-WacValidationResult -Level "OK" -Code "PortPlanValid" -Message "Port plan is valid."
}
