<#
.SYNOPSIS
    Creates a visual dashboard for migration monitoring and reporting. 
.DESCRIPTION
    Generates HTML dashboard with charts, metrics, and real-time migration status based on migration report data.
    Utilizes Bootstrap and Chart.js for responsive design and interactive visualizations.
.PARAMETER MigrationReport
    Comprehensive migration report data
.PARAMETER OutputPath
    Path for dashboard files
.PARAMETER DashboardTitle
    Title for the migration dashboard
#>

param(
    [Parameter(Mandatory=$true)]
    [hashtable]$MigrationReport,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Dashboard",
    
    [Parameter(Mandatory=$false)]
    [string]$DashboardTitle = "Storage Migration Dashboard"
)

function Write-DashboardLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$OutputPath\dashboard-generation.log" -Append
}

function New-HTMLDashboard {
    param([hashtable]$Report, [string]$Title)
    
    try {
        Write-DashboardLog "Generating HTML dashboard"
        
        $executive = $Report.ExecutiveSummary
        $technical = $Report.TechnicalDetails
        $risks = $Report.RiskAnalysis
        $costs = $Report.CostAnalysis
        
        # Calculate status color
        $statusColor = switch ($executive.Status) {
            "Pass" { "success" }
            "Warning" { "warning" }
            "Fail" { "danger" }
            default { "secondary" }
        }
        
        $riskColor = switch ($risks.RiskLevel) {
            "Low" { "success" }
            "Medium" { "warning" }
            "High" { "danger" }
            default { "secondary" }
        }
        
        $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        .dashboard-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem 0;
            margin-bottom: 2rem;
        }
        .metric-card {
            border: none;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            margin-bottom: 1.5rem;
            transition: transform 0.2s;
        }
        .metric-card:hover {
            transform: translateY(-2px);
        }
        .metric-value {
            font-size: 2rem;
            font-weight: bold;
            margin-bottom: 0.5rem;
        }
        .chart-container {
            position: relative;
            height: 300px;
            margin-bottom: 2rem;
        }
        .status-badge {
            font-size: 0.9rem;
            padding: 0.5rem 1rem;
        }
    </style>
</head>
<body>
    <div class="dashboard-header">
        <div class="container">
            <div class="row align-items-center">
                <div class="col">
                    <h1 class="display-4">$Title</h1>
                    <p class="lead">Migration completed on: $(Get-Date -Format 'MMMM d, yyyy')</p>
                </div>
                <div class="col-auto">
                    <span class="badge status-badge bg-$statusColor">$($executive.Status.ToUpper())</span>
                </div>
            </div>
        </div>
    </div>

    <div class="container">
        <!-- Executive Summary -->
        <div class="row mb-4">
            <div class="col-12">
                <div class="card metric-card">
                    <div class="card-body">
                        <h3 class="card-title">Executive Summary</h3>
                        <div class="row">
                            <div class="col-md-3">
                                <div class="text-center">
                                    <div class="metric-value text-primary">$($executive.TotalDataMigratedGB) GB</div>
                                    <div class="text-muted">Data Migrated</div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="text-center">
                                    <div class="metric-value text-info">$($executive.MigrationDuration)h</div>
                                    <div class="text-muted">Duration</div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="text-center">
                                    <div class="metric-value text-success">$($executive.SuccessRate)%</div>
                                    <div class="text-muted">Success Rate</div>
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="text-center">
                                    <div class="metric-value text-$riskColor">$($risks.RiskLevel)</div>
                                    <div class="text-muted">Risk Level</div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Performance Metrics -->
        <div class="row">
            <div class="col-md-6">
                <div class="card metric-card">
                    <div class="card-body">
                        <h5 class="card-title">Validation Results</h5>
                        <div class="chart-container">
                            <canvas id="validationChart"></canvas>
                        </div>
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="card metric-card">
                    <div class="card-body">
                        <h5 class="card-title">Cost Analysis</h5>
                        <div class="chart-container">
                            <canvas id="costChart"></canvas>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Technical Details -->
        <div class="row mt-4">
            <div class="col-md-6">
                <div class="card metric-card">
                    <div class="card-body">
                        <h5 class="card-title">Technical Details</h5>
                        <table class="table table-sm">
                            <tr>
                                <td><strong>Migration Type:</strong></td>
                                <td>$($executive.MigrationType)</td>
                            </tr>
                            <tr>
                                <td><strong>Source:</strong></td>
                                <td>$($technical.SourceDetails.Path)</td>
                            </tr>
                            <tr>
                                <td><strong>Target:</strong></td>
                                <td>$($technical.TargetDetails.Path)</td>
                            </tr>
                            <tr>
                                <td><strong>Total Files:</strong></td>
                                <td>$($technical.SourceDetails.TotalFiles.ToString("N0"))</td>
                            </tr>
                            <tr>
                                <td><strong>Transfer Rate:</strong></td>
                                <td>$($technical.MigrationDetails.AverageTransferRateMBps) MB/s</td>
                            </tr>
                        </table>
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="card metric-card">
                    <div class="card-body">
                        <h5 class="card-title">Risk Analysis</h5>
                        <div class="mb-3">
                            <span class="badge bg-$riskColor">$($risks.RiskLevel) Risk</span>
                            <span class="badge bg-info">$($risks.IdentifiedRisks.Count) Issues</span>
                        </div>
                        <div style="max-height: 200px; overflow-y: auto;">
"@
        
        # Add risk items
        if ($risks.IdentifiedRisks.Count -gt 0) {
            foreach ($risk in $risks.IdentifiedRisks) {
                $riskBadgeColor = switch ($risk.Severity) {
                    "High" { "danger" }
                    "Medium" { "warning" }
                    "Low" { "info" }
                    default { "secondary" }
                }
                $htmlContent += @"
                            <div class="alert alert-$riskBadgeColor alert-sm mb-2">
                                <strong>$($risk.Category):</strong> $($risk.Description)
                            </div>
"@
            }
        } else {
            $htmlContent += @'
                            <div class="alert alert-success alert-sm mb-2">
                                No significant risks identified
                            </div>
'@
        }
        
        $htmlContent += @"
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Lessons Learned -->
        <div class="row mt-4">
            <div class="col-12">
                <div class="card metric-card">
                    <div class="card-body">
                        <h5 class="card-title">Lessons Learned</h5>
                        <div class="row">
"@
        
        # Add lessons learned
        $successLessons = $Report.LessonsLearned | Where-Object { $_.Type -eq "Success" }
        $improvementLessons = $Report.LessonsLearned | Where-Object { $_.Type -eq "Improvement" }
        
        if ($successLessons.Count -gt 0) {
            $htmlContent += @"
                            <div class="col-md-6">
                                <h6 class="text-success">Successes</h6>
                                <ul>
"@
            foreach ($lesson in $successLessons) {
                $htmlContent += "<li><strong>$($lesson.Lesson)</strong><br><small>$($lesson.Recommendation)</small></li>"
            }
            $htmlContent += @"
                                </ul>
                            </div>
"@
        }
        
        if ($improvementLessons.Count -gt 0) {
            $htmlContent += @"
                            <div class="col-md-6">
                                <h6 class="text-warning">Improvements</h6>
                                <ul>
"@
            foreach ($lesson in $improvementLessons) {
                $htmlContent += "<li><strong>$($lesson.Lesson)</strong><br><small>$($lesson.Recommendation)</small></li>"
            }
            $htmlContent += @"
                                </ul>
                            </div>
"@
        }
        
        $htmlContent += @"
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Next Steps -->
        <div class="row mt-4">
            <div class="col-12">
                <div class="card metric-card">
                    <div class="card-body">
                        <h5 class="card-title">Next Steps</h5>
                        <ol>
"@
        
        foreach ($step in $Report.OverallAssessment.NextSteps) {
            $htmlContent += "<li>$step</li>"
        }
        
        $htmlContent += @"
                        </ol>
                    </div>
                </div>
            </div>
        </div>

        <!-- Footer -->
        <footer class="mt-5 mb-4 text-center text-muted">
            <p>Report generated on $((Get-Date).ToString('MMMM d, yyyy at h:mm tt'))</p>
        </footer>
    </div>

    <script>
        // Validation Results Chart
        const validationCtx = document.getElementById('validationChart').getContext('2d');
        const validationChart = new Chart(validationCtx, {
            type: 'doughnut',
            data: {
                labels: ['File Count Match', 'Size Accuracy', 'Data Integrity', 'Permission Accuracy'],
                datasets: [{
                    data: [
                        $($technical.PerformanceMetrics.FileCountAccuracy ? 100 : 0),
                        $($technical.PerformanceMetrics.FileSizeAccuracy -replace '%',''),
                        $($technical.PerformanceMetrics.DataIntegrity -replace '%',''),
                        $($technical.PerformanceMetrics.PermissionAccuracy -replace '%','')
                    ],
                    backgroundColor: [
                        '#4e73df',
                        '#1cc88a',
                        '#36b9cc',
                        '#f6c23e'
                    ],
                    hoverBackgroundColor: [
                        '#2e59d9',
                        '#17a673',
                        '#2c9faf',
                        '#dda20a'
                    ]
                }]
            },
            options: {
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });

        // Cost Analysis Chart
        const costCtx = document.getElementById('costChart').getContext('2d');
        const costChart = new Chart(costCtx, {
            type: 'bar',
            data: {
                labels: ['Storage', 'Network', 'Compute', 'Labor'],
                datasets: [{
                    label: 'Estimated Cost',
                    data: [
                        $($costs.CostBreakdown.InfrastructureCosts.Storage.Estimated),
                        $($costs.CostBreakdown.InfrastructureCosts.Network.Estimated),
                        $($costs.CostBreakdown.InfrastructureCosts.Compute.Estimated),
                        $($costs.CostBreakdown.OperationalCosts.Labor.Estimated)
                    ],
                    backgroundColor: 'rgba(78, 115, 223, 0.5)',
                    borderColor: 'rgba(78, 115, 223, 1)',
                    borderWidth: 1
                }, {
                    label: 'Actual Cost',
                    data: [
                        $($costs.CostBreakdown.InfrastructureCosts.Storage.Actual),
                        $($costs.CostBreakdown.InfrastructureCosts.Network.Actual),
                        $($costs.CostBreakdown.InfrastructureCosts.Compute.Actual),
                        $($costs.CostBreakdown.OperationalCosts.Labor.Actual)
                    ],
                    backgroundColor: 'rgba(28, 200, 138, 0.5)',
                    borderColor: 'rgba(28, 200, 138, 1)',
                    borderWidth: 1
                }]
            },
            options: {
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Cost ($)'
                        }
                    }
                }
            }
        });
    </script>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
"@
        
        return $htmlContent
    }
    catch {
        Write-DashboardLog "HTML dashboard generation failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Export-Dashboard {
    param([string]$HtmlContent, [string]$OutputPath, [hashtable]$Report)
    
    try {
        Write-DashboardLog "Exporting dashboard files"
        
        # Create output directory
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force
        }
        
        # Export HTML dashboard
        $htmlFile = Join-Path $OutputPath "migration-dashboard-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
        $HtmlContent | Out-File -FilePath $htmlFile -Encoding UTF8
        
        # Export simplified JSON for potential API consumption
        $jsonFile = Join-Path $OutputPath "dashboard-data-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $dashboardData = @{
            Metadata = @{
                Generated = Get-Date
                Version = "1.0"
            }
            Metrics = @{
                TotalDataGB = $Report.ExecutiveSummary.TotalDataMigratedGB
                DurationHours = $Report.ExecutiveSummary.MigrationDuration
                SuccessRate = $Report.ExecutiveSummary.SuccessRate
                Status = $Report.ExecutiveSummary.Status
                RiskLevel = $Report.RiskAnalysis.RiskLevel
            }
            Technical = @{
                MigrationType = $Report.ExecutiveSummary.MigrationType
                SourcePath = $Report.TechnicalDetails.SourceDetails.Path
                TargetPath = $Report.TechnicalDetails.TargetDetails.Path
                FileCount = $Report.TechnicalDetails.SourceDetails.TotalFiles
            }
        }
        $dashboardData | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonFile
        
        return @{
            HtmlFile = $htmlFile
            JsonFile = $jsonFile
        }
    }
    catch {
        Write-DashboardLog "Dashboard export failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Main execution
try {
    Write-DashboardLog "Starting migration dashboard generation"
    
    # Generate HTML dashboard
    $htmlContent = New-HTMLDashboard -Report $MigrationReport -Title $DashboardTitle
    
    # Export dashboard files
    $exportedFiles = Export-Dashboard -HtmlContent $htmlContent -OutputPath $OutputPath -Report $MigrationReport
    
    # Display summary
    Write-Host "`n=== DASHBOARD GENERATION COMPLETE ===" -ForegroundColor Green
    Write-Host "Dashboard Files:" -ForegroundColor Cyan
    Write-Host "  HTML Dashboard: $($exportedFiles.HtmlFile)" -ForegroundColor White
    Write-Host "  JSON Data: $($exportedFiles.JsonFile)" -ForegroundColor White
    Write-Host "`nTo view the dashboard:" -ForegroundColor Yellow
    Write-Host "  Open in browser: $($exportedFiles.HtmlFile)" -ForegroundColor White
    
    Write-DashboardLog "Migration dashboard generation completed successfully" -Level "SUCCESS"
    
    return $exportedFiles
}
catch {
    Write-DashboardLog "Migration dashboard generation failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}