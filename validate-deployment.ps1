#!/usr/bin/env pwsh
# Comprehensive Deployment Validation Test Suite
# Real Estate Intelligence - Production Validation

param(
    [string]$ServiceUrl = "",
    [string]$Region = "us-east1",
    [string]$Project = "infinity-x-one-systems",
    [string]$ServiceName = "real-estate-intelligence"
)

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   REAL ESTATE INTELLIGENCE - DEPLOYMENT VALIDATION SUITE   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Test Results
$script:passed = 0
$script:failed = 0
$script:warnings = 0

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Url,
        [int]$ExpectedStatus = 200,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null
    )
    
    Write-Host "  Testing: $Name" -ForegroundColor Yellow -NoNewline
    
    try {
        $params = @{
            Uri = $Url
            Method = $Method
            Headers = $Headers
            TimeoutSec = 30
            ErrorAction = 'Stop'
        }
        
        if ($Body) {
            $params['Body'] = $Body
            $params['ContentType'] = 'application/json'
        }
        
        $response = Invoke-WebRequest @params
        
        if ($response.StatusCode -eq $ExpectedStatus) {
            Write-Host " ✅ PASSED" -ForegroundColor Green
            $script:passed++
            return @{
                Success = $true
                StatusCode = $response.StatusCode
                Content = $response.Content
                ResponseTime = $response.Headers['X-Response-Time']
            }
        } else {
            Write-Host " ❌ FAILED (Status: $($response.StatusCode), Expected: $ExpectedStatus)" -ForegroundColor Red
            $script:failed++
            return @{
                Success = $false
                StatusCode = $response.StatusCode
                Error = "Unexpected status code"
            }
        }
    }
    catch {
        Write-Host " ❌ FAILED ($($_.Exception.Message))" -ForegroundColor Red
        $script:failed++
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Get Service URL if not provided
if ([string]::IsNullOrEmpty($ServiceUrl)) {
    Write-Host "📡 Retrieving Service URL..." -ForegroundColor Cyan
    $ServiceUrl = gcloud run services describe $ServiceName `
        --region=$Region `
        --project=$Project `
        --format="value(status.url)"
    
    if ([string]::IsNullOrEmpty($ServiceUrl)) {
        Write-Host "`n❌ ERROR: Could not retrieve service URL" -ForegroundColor Red
        exit 1
    }
    Write-Host "   URL: $ServiceUrl`n" -ForegroundColor Gray
}

Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Gray

# TEST 1: Health Check
Write-Host "1️⃣  INFRASTRUCTURE TESTS" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Gray
$healthResult = Test-Endpoint -Name "Health Check" -Url "$ServiceUrl/health"

# TEST 2: Service Status
$statusResult = Test-Endpoint -Name "Service Status" -Url "$ServiceUrl/status"

# TEST 3: Metrics Endpoint
$metricsResult = Test-Endpoint -Name "Metrics" -Url "$ServiceUrl/metrics"

Write-Host "`n2️⃣  API ENDPOINT TESTS" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Gray

# TEST 4: AI Query
$aiQueryResult = Test-Endpoint -Name "AI Query" `
    -Url "$ServiceUrl/api/query" `
    -Method "POST" `
    -Body '{"query":"What is the real estate market outlook?","context":"general"}'

# TEST 5: Memory System
$memoryResult = Test-Endpoint -Name "Memory System" -Url "$ServiceUrl/api/memory/status"

# TEST 6: RAG Knowledge
$ragResult = Test-Endpoint -Name "RAG Knowledge Base" -Url "$ServiceUrl/api/rag/health"

Write-Host "`n3️⃣  CLOUD RUN SERVICE HEALTH" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Gray

# Get Service Details
Write-Host "  Cloud Run Service Details:" -ForegroundColor Yellow
$serviceInfo = gcloud run services describe $ServiceName `
    --region=$Region `
    --project=$Project `
    --format="json" | ConvertFrom-Json

$latestRevision = $serviceInfo.status.latestReadyRevisionName
$traffic = $serviceInfo.status.traffic[0].percent
$conditions = $serviceInfo.status.conditions

Write-Host "    Revision: $latestRevision" -ForegroundColor Gray
Write-Host "    Traffic: $traffic%" -ForegroundColor Gray

foreach ($condition in $conditions) {
    $status = $condition.status
    $type = $condition.type
    $color = if ($status -eq "True") { "Green" } else { "Red" }
    $icon = if ($status -eq "True") { "✅" } else { "❌" }
    Write-Host "    $icon $type`: $status" -ForegroundColor $color
}

Write-Host "`n4️⃣  CONTAINER & RESOURCE VALIDATION" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Gray

# Check Container Logs for Errors
Write-Host "  Checking Recent Container Logs:" -ForegroundColor Yellow
$recentLogs = gcloud logging read `
    "resource.type=cloud_run_revision AND resource.labels.service_name=$ServiceName AND severity>=ERROR" `
    --limit=5 `
    --project=$Project `
    --format="table(timestamp,severity,textPayload)" `
    --freshness=5m

if ($null -eq $recentLogs -or $recentLogs -match "Listed 0 items") {
    Write-Host "    ✅ No errors in last 5 minutes" -ForegroundColor Green
    $script:passed++
} else {
    Write-Host "    ⚠️  Recent errors detected:" -ForegroundColor Yellow
    Write-Host $recentLogs -ForegroundColor Gray
    $script:warnings++
}

# Check Resource Usage
Write-Host "`n  Resource Configuration:" -ForegroundColor Yellow
$container = $serviceInfo.spec.template.spec.containers[0]
Write-Host "    Memory: $($container.resources.limits.memory)" -ForegroundColor Gray
Write-Host "    CPU: $($container.resources.limits.cpu)" -ForegroundColor Gray
Write-Host "    Port: $($container.ports[0].containerPort)" -ForegroundColor Gray
Write-Host "    Min Instances: $($serviceInfo.spec.template.metadata.annotations.'autoscaling.knative.dev/minScale')" -ForegroundColor Gray
Write-Host "    Max Instances: $($serviceInfo.spec.template.metadata.annotations.'autoscaling.knative.dev/maxScale')" -ForegroundColor Gray

Write-Host "`n5️⃣  ENVIRONMENT & CONFIGURATION" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Gray

Write-Host "  Environment Variables:" -ForegroundColor Yellow
$envVars = $container.env
foreach ($env in $envVars | Select-Object -First 10) {
    if ($env.name) {
        $value = if ($env.value) { $env.value } else { "<from secret>" }
        Write-Host "    $($env.name): $value" -ForegroundColor Gray
    }
}

Write-Host "`n6️⃣  DEPENDENCY & MODULE VALIDATION" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────" -ForegroundColor Gray

# Check for MODULE_NOT_FOUND errors
Write-Host "  Checking for Module Errors:" -ForegroundColor Yellow
$moduleErrors = gcloud logging read `
    "resource.type=cloud_run_revision AND resource.labels.service_name=$ServiceName AND textPayload=~'MODULE_NOT_FOUND'" `
    --limit=1 `
    --project=$Project `
    --format="value(textPayload)" `
    --freshness=10m

if ([string]::IsNullOrEmpty($moduleErrors)) {
    Write-Host "    ✅ No module errors detected" -ForegroundColor Green
    $script:passed++
} else {
    Write-Host "    ❌ Module errors found:" -ForegroundColor Red
    Write-Host $moduleErrors -ForegroundColor Gray
    $script:failed++
}

# TEST SUMMARY
Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                     VALIDATION SUMMARY                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "  ✅ Passed:   $script:passed" -ForegroundColor Green
Write-Host "  ❌ Failed:   $script:failed" -ForegroundColor $(if($script:failed -eq 0){"Green"}else{"Red"})
Write-Host "  ⚠️  Warnings: $script:warnings" -ForegroundColor $(if($script:warnings -eq 0){"Green"}else{"Yellow"})

$total = $script:passed + $script:failed
$successRate = if ($total -gt 0) { [math]::Round(($script:passed / $total) * 100, 2) } else { 0 }

Write-Host "`n  Success Rate: $successRate%" -ForegroundColor $(if($successRate -ge 80){"Green"}elseif($successRate -ge 60){"Yellow"}else{"Red"})

if ($script:failed -eq 0 -and $script:warnings -eq 0) {
    Write-Host "`n🎉 ALL TESTS PASSED! Deployment is healthy and operational." -ForegroundColor Green -BackgroundColor Black
    exit 0
} elseif ($script:failed -eq 0) {
    Write-Host "`n⚠️  All tests passed with warnings. Review warnings above." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "`n❌ VALIDATION FAILED. Please review failed tests above." -ForegroundColor Red -BackgroundColor Black
    exit 1
}
