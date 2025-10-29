<#
.SYNOPSIS
    Generates comprehensive migration reports for storage migration projects.
.DESCRIPTION
    Creates detailed reports with metrics, analytics, and recommendations based on data from assessment,
    planning, execution, and validation phases of storage migration projects. Outputs reports in multiple formats
    including JSON and CSV for executive and technical audiences.
.PARAMETER AssessmentData
    Data from the assessment phase
.PARAMETER PlanningData
    Data from the planning phase
.PARAMETER ExecutionResults
    Results from the execution phase
.PARAMETER ValidationResults
    Results from the validation phase
.PARAMETER OutputPath
    Path for report files
#>

param(
    [Parameter(Mandatory=$true)]
    [hashtable]$AssessmentData,
    
    [Parameter(Mandatory=$true)]
    [hashtable]$PlanningData,
    
    [Parameter(Mandatory=$true)]
    [hashtable]$ExecutionResults,
    
    [Parameter(Mandatory=$true)]
    [hashtable]$ValidationResults,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\Reports"
)

function Write-ReportLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    $logEntry = "[$timestamp] [$Level] $Message"
    $logEntry | Out-File -FilePath "$OutputPath\migration-report.log" -Append
}

function New-ExecutiveSummary {
    param([hashtable]$Assessment, [hashtable]$Planning, [hashtable]$Execution, [hashtable]$Validation)
    
    try {
        Write-ReportLog "Generating executive summary"
        
        $totalDataGB = $Planning.MigrationPlan.Timeline.TotalSizeGB
        $migrationDuration = $Validation.ValidationDate - $Assessment.AnalysisDate
        $successRate = $Validation.OverallScore
        
        $summary = @{
            ReportDate = Get-Date
            Project = "Storage Migration"
            MigrationType = $Planning.MigrationPlan.MigrationType
            TotalDataMigratedGB = $totalDataGB
            MigrationDuration = [math]::Round($migrationDuration.TotalHours, 2)
            SuccessRate = $successRate
            Status = $Validation.ValidationStatus
            KeyMetrics = @{
                "Data Transfer Rate" = "$([math]::Round($totalDataGB / $migrationDuration.TotalHours, 2)) GB/hour"
                "Validation Score" = "$successRate%"
                "Files Processed" = $Validation.FileCountComparison.SourceFileCount
                "Overall Efficiency" = if ($successRate -ge 95) { "Excellent" } elseif ($successRate -ge 80) { "Good" } else { "Needs Improvement" }
            }
            Recommendations = @()
        }
        
        # Add recommendations based on results
        if ($successRate -lt 95) {
            $summary.Recommendations += "Review validation results and address any discrepancies"
        }
        
        if ($migrationDuration.TotalHours -gt 24) {
            $summary.Recommendations += "Consider optimizing network bandwidth for future migrations"
        }
        
        if ($Validation.FileCountComparison.FileCountMatch -eq $false) {
            $summary.Recommendations += "Investigate missing or extra files in target storage"
        }
        
        return $summary
    }
    catch {
        Write-ReportLog "Executive summary generation failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function New-TechnicalDetails {
    param([hashtable]$Assessment, [hashtable]$Planning, [hashtable]$Execution, [hashtable]$Validation)
    
    try {
        Write-ReportLog "Generating technical details"
        
        $technical = @{
            SourceDetails = @{
                Path = $Assessment.SourcePath
                FileSystem = $Assessment.FileSystem.DriveType
                TotalSizeGB = $Assessment.TotalSizeGB
                TotalFiles = $Assessment.TotalFiles
                Accessibility = $Assessment.Accessibility
            }
            TargetDetails = @{
                Path = $Planning.MigrationPlan.TargetPath
                Type = $Planning.MigrationPlan.MigrationType
                ValidationScore = $Validation.OverallScore
            }
            MigrationDetails = @{
                Method = $Planning.MigrationPlan.MigrationType
                StartTime = $Assessment.AnalysisDate
                EndTime = $Validation.ValidationDate
                DurationHours = [math]::Round(($Validation.ValidationDate - $Assessment.AnalysisDate).TotalHours, 2)
                TotalDataTransferredGB = $Planning.MigrationPlan.Timeline.TotalSizeGB
                AverageTransferRateMBps = [math]::Round(($Planning.MigrationPlan.Timeline.TotalSizeGB * 1024) / ($Validation.ValidationDate - $Assessment.AnalysisDate).TotalSeconds, 2)
            }
            PerformanceMetrics = @{
                FileCountAccuracy = $Validation.FileCountComparison.FileCountMatch
                FileSizeAccuracy = "$($Validation.FileSizeComparison.SizeMatchPercentage)%"
                DataIntegrity = "$($Validation.ChecksumComparison.ChecksumMatchPercentage)%"
                PermissionAccuracy = "$($Validation.PermissionComparison.PermissionMatchPercentage)%"
            }
        }
        
        return $technical
    }
    catch {
        Write-ReportLog "Technical details generation failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function New-RiskAnalysis {
    param([hashtable]$Planning, [hashtable]$Validation)
    
    try {
        Write-ReportLog "Generating risk analysis"
        
        $risks = @()
        
        # Data integrity risks
        if ($Validation.ChecksumComparison.ChecksumMatchPercentage -lt 100) {
            $risks += @{
                Category = "Data Integrity"
                Description = "Checksum mismatches detected in migrated data"
                Severity = if ($Validation.ChecksumComparison.ChecksumMatchPercentage -lt 95) { "High" } else { "Medium" }
                Impact = "Potential data corruption or loss"
                Recommendation = "Review checksum mismatch details and consider re-migrating affected files"
            }
        }
        
        # Permission risks
        if ($Validation.PermissionComparison.PermissionMatchPercentage -lt 100) {
            $risks += @{
                Category = "Security"
                Description = "Permission inconsistencies between source and target"
                Severity = "Medium"
                Impact = "Potential access control issues"
                Recommendation = "Review and reconcile permission differences"
            }
        }
        
        # Performance risks
        if ($Validation.OverallScore -lt 80) {
            $risks += @{
                Category = "Performance"
                Description = "Low overall validation score indicates potential issues"
                Severity = "High"
                Impact = "Migration may not meet business requirements"
                Recommendation = "Conduct thorough investigation and remediation"
            }
        }
        
        return @{
            IdentifiedRisks = $risks
            RiskLevel = if ($risks.Count -eq 0) { "Low" } elseif ($risks.Severity -contains "High") { "High" } else { "Medium" }
            MitigationStatus = if ($risks.Count -eq 0) { "Not Required" } else { "Required" }
        }
    }
    catch {
        Write-ReportLog "Risk analysis generation failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function New-CostAnalysis {
    param([hashtable]$Planning, [hashtable]$Execution)
    
    try {
        Write-ReportLog "Generating cost analysis"
        
        $totalSizeGB = $Planning.MigrationPlan.Timeline.TotalSizeGB
        $migrationDuration = $Planning.MigrationPlan.Timeline.TotalEstimatedHours
        
        $costBreakdown = @{
            InfrastructureCosts = @{
                Storage = @{ Estimated = [math]::Round($totalSizeGB * 0.02, 2); Actual = [math]::Round($totalSizeGB * 0.02, 2) }
                Network = @{ Estimated = [math]::Round($totalSizeGB * 0.05, 2); Actual = [math]::Round($totalSizeGB * 0.05, 2) }
                Compute = @{ Estimated = 50; Actual = 50 }
            }
            OperationalCosts = @{
                Labor = @{ Estimated = [math]::Round($migrationDuration * 100, 2); Actual = [math]::Round($migrationDuration * 100, 2) }  # $100/hour
                Tools = @{ Estimated = 0; Actual = 0 }
            }
        }
        
        $totalEstimated = ($costBreakdown.InfrastructureCosts.Values.Estimated | Measure-Object -Sum).Sum + 
                         ($costBreakdown.OperationalCosts.Values.Estimated | Measure-Object -Sum).Sum
        
        $totalActual = ($costBreakdown.InfrastructureCosts.Values.Actual | Measure-Object -Sum).Sum + 
                      ($costBreakdown.OperationalCosts.Values.Actual | Measure-Object -Sum).Sum
        
        return @{
            CostBreakdown = $costBreakdown
            TotalEstimated = $totalEstimated
            TotalActual = $totalActual
            Variance = $totalActual - $totalEstimated
            VariancePercentage = if ($totalEstimated -gt 0) { [math]::Round(($totalActual - $totalEstimated) / $totalEstimated * 100, 2) } else { 0 }
        }
    }
    catch {
        Write-ReportLog "Cost analysis generation failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function New-LessonsLearned {
    param([hashtable]$Assessment, [hashtable]$Planning, [hashtable]$Execution, [hashtable]$Validation)
    
    try {
        Write-ReportLog "Generating lessons learned"
        
        $lessons = @()
        
        # Positive lessons
        if ($Validation.OverallScore -ge 95) {
            $lessons += @{
                Type = "Success"
                Lesson = "The chosen migration method ($($Planning.MigrationPlan.MigrationType)) was effective for this data volume"
                Recommendation = "Consider using the same approach for similar migrations"
            }
        }
        
        if ($Execution.MigrationResult.Success -eq $true) {
            $lessons += @{
                Type = "Success"
                Lesson = "Migration execution completed without major issues"
                Recommendation = "Maintain the current execution procedures"
            }
        }
        
        # Improvement opportunities
        if ($Validation.FileCountComparison.FileCountMatch -eq $false) {
            $lessons += @{
                Type = "Improvement"
                Lesson = "File count discrepancies were identified during validation"
                Recommendation = "Enhance pre-migration assessment to better account for file exclusions"
            }
        }
        
        if ($Validation.Duration.TotalMinutes -gt 60) {
            $lessons += @{
                Type = "Improvement"
                Lesson = "Validation process took longer than expected"
                Recommendation = "Optimize validation scripts and consider parallel processing"
            }
        }
        
        return $lessons
    }
    catch {
        Write-ReportLog "Lessons learned generation failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Export-Reports {
    param([hashtable]$Report, [string]$OutputPath)
    
    try {
        Write-ReportLog "Exporting reports to: $OutputPath"
        
        # Create output directory
        if (!(Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force
        }
        
        # Export full report as JSON
        $jsonReport = Join-Path $OutputPath "migration-full-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $Report | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReport
        
        # Export executive summary as CSV
        $executiveCsv = Join-Path $OutputPath "executive-summary-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $executiveData = @(
            [PSCustomObject]@{
                Metric = "Migration Type"
                Value = $Report.ExecutiveSummary.MigrationType
            },
            [PSCustomObject]@{
                Metric = "Total Data Migrated (GB)"
                Value = $Report.ExecutiveSummary.TotalDataMigratedGB
            },
            [PSCustomObject]@{
                Metric = "Migration Duration (Hours)"
                Value = $Report.ExecutiveSummary.MigrationDuration
            },
            [PSCustomObject]@{
                Metric = "Success Rate (%)"
                Value = $Report.ExecutiveSummary.SuccessRate
            },
            [PSCustomObject]@{
                Metric = "Overall Status"
                Value = $Report.ExecutiveSummary.Status
            }
        )
        $executiveData | Export-Csv -Path $executiveCsv -NoTypeInformation
        
        # Export technical details as CSV
        $technicalCsv = Join-Path $OutputPath "technical-details-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $technicalData = @(
            [PSCustomObject]@{
                Category = "Source Path"
                Value = $Report.TechnicalDetails.SourceDetails.Path
            },
            [PSCustomObject]@{
                Category = "Target Path"
                Value = $Report.TechnicalDetails.TargetDetails.Path
            },
            [PSCustomObject]@{
                Category = "Total Files"
                Value = $Report.TechnicalDetails.SourceDetails.TotalFiles
            },
            [PSCustomObject]@{
                Category = "Total Size (GB)"
                Value = $Report.TechnicalDetails.SourceDetails.TotalSizeGB
            },
            [PSCustomObject]@{
                Category = "File Count Accuracy"
                Value = $Report.TechnicalDetails.PerformanceMetrics.FileCountAccuracy
            },
            [PSCustomObject]@{
                Category = "Data Integrity Score"
                Value = $Report.TechnicalDetails.PerformanceMetrics.DataIntegrity
            }
        )
        $technicalData | Export-Csv -Path $technicalCsv -NoTypeInformation
        
        return @{
            JsonReport = $jsonReport
            ExecutiveCsv = $executiveCsv
            TechnicalCsv = $technicalCsv
        }
    }
    catch {
        Write-ReportLog "Report export failed: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

# Main execution
try {
    Write-ReportLog "Starting migration report generation"
    
    # Create output directory
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force
    }
    
    # Generate report sections
    $executiveSummary = New-ExecutiveSummary -Assessment $AssessmentData -Planning $PlanningData -Execution $ExecutionResults -Validation $ValidationResults
    $technicalDetails = New-TechnicalDetails -Assessment $AssessmentData -Planning $PlanningData -Execution $ExecutionResults -Validation $ValidationResults
    $riskAnalysis = New-RiskAnalysis -Planning $PlanningData -Validation $ValidationResults
    $costAnalysis = New-CostAnalysis -Planning $PlanningData -Execution $ExecutionResults
    $lessonsLearned = New-LessonsLearned -Assessment $AssessmentData -Planning $PlanningData -Execution $ExecutionResults -Validation $ValidationResults
    
    # Compile comprehensive report
    $migrationReport = @{
        ReportMetadata = @{
            GeneratedDate = Get-Date
            ReportVersion = "1.0"
            Scope = "Storage Migration"
        }
        ExecutiveSummary = $executiveSummary
        TechnicalDetails = $technicalDetails
        RiskAnalysis = $riskAnalysis
        CostAnalysis = $costAnalysis
        LessonsLearned = $lessonsLearned
        OverallAssessment = @{
            Success = $ValidationResults.ValidationStatus -eq "Pass"
            ConfidenceLevel = if ($ValidationResults.OverallScore -ge 95) { "High" } elseif ($ValidationResults.OverallScore -ge 80) { "Medium" } else { "Low" }
            NextSteps = @(
                "Monitor target storage performance for 7 days",
                "Validate application functionality with migrated data",
                "Update documentation with migration details",
                "Schedule follow-up review in 30 days"
            )
        }
    }
    
    # Export reports
    $exportedFiles = Export-Reports -Report $migrationReport -OutputPath $OutputPath
    
    # Display summary
    Write-Host "`n=== MIGRATION REPORT GENERATION COMPLETE ===" -ForegroundColor Green
    Write-Host "Executive Summary:" -ForegroundColor Cyan
    Write-Host "  Migration Type: $($executiveSummary.MigrationType)" -ForegroundColor Yellow
    Write-Host "  Data Migrated: $($executiveSummary.TotalDataMigratedGB) GB" -ForegroundColor Yellow
    Write-Host "  Duration: $($executiveSummary.MigrationDuration) hours" -ForegroundColor Yellow
    Write-Host "  Success Rate: $($executiveSummary.SuccessRate)%" -ForegroundColor $(if ($executiveSummary.SuccessRate -ge 95) { "Green" } else { "Yellow" })
    Write-Host "  Status: $($executiveSummary.Status)" -ForegroundColor $(if ($executiveSummary.Status -eq "Pass") { "Green" } else { "Red" })
    
    Write-Host "`nRisk Analysis:" -ForegroundColor Cyan
    Write-Host "  Risk Level: $($riskAnalysis.RiskLevel)" -ForegroundColor $(if ($riskAnalysis.RiskLevel -eq "Low") { "Green" } else { "Yellow" })
    Write-Host "  Identified Risks: $($riskAnalysis.IdentifiedRisks.Count)" -ForegroundColor Yellow
    
    Write-Host "`nCost Analysis:" -ForegroundColor Cyan
    Write-Host "  Total Cost: $$($costAnalysis.TotalActual)" -ForegroundColor Yellow
    Write-Host "  Variance: $($costAnalysis.VariancePercentage)%" -ForegroundColor $(if ($costAnalysis.VariancePercentage -le 10) { "Green" } else { "Yellow" })
    
    Write-Host "`nReport Files:" -ForegroundColor Cyan
    foreach ($file in $exportedFiles.GetEnumerator()) {
        Write-Host "  - $($file.Key): $($file.Value)" -ForegroundColor White
    }
    
    Write-ReportLog "Migration report generation completed successfully" -Level "SUCCESS"
    
    return $migrationReport
}
catch {
    Write-ReportLog "Migration report generation failed: $($_.Exception.Message)" -Level "ERROR"
    throw
}