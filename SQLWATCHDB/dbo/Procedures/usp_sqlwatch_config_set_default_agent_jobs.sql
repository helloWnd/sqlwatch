﻿CREATE PROCEDURE [dbo].[usp_sqlwatch_config_set_default_agent_jobs]
	@remove_existing bit = 0
AS

/* create jobs */
declare @sql varchar(max)
declare @job_description nvarchar(255) = 'https://sqlwatch.io'
declare @job_category nvarchar(255) = 'Data Collector'
declare @database_name sysname = '$(DatabaseName)'
declare @command nvarchar(4000)

declare @server nvarchar(255)
set @server = @@SERVERNAME


set @sql = ''
if @remove_existing = 1
	begin
		select @sql = @sql + 'exec msdb.dbo.sp_delete_job @job_id=N''' + convert(varchar(255),job_id) + ''';' 
		from msdb.dbo.sysjobs
where name like 'SQLWATCH-%'

		exec (@sql)
	end

set @sql = ''
create table #jobs (
	job_name sysname primary key,
	freq_type int, 
	freq_interval int, 
	freq_subday_type int, 
	freq_subday_interval int, 
	freq_relative_interval int, 
	freq_recurrence_factor int, 
	active_start_date int, 
	active_end_date int, 
	active_start_time int, 
	active_end_time int,
	job_enabled tinyint,
	)

create table #steps (
	step_name sysname,
	step_id int,
	job_name sysname,
	step_subsystem sysname,
	step_command varchar(max)
	)


/* job definition */
insert into #jobs
	values	('SQLWATCH-LOGGER-WHOISACTIVE',		4, 1, 2, 15, 0, 0, 20180101, 99991231, 0,	235959, 0),
			('SQLWATCH-LOGGER-PERFORMANCE',		4, 1, 4, 1,  0, 1, 20180101, 99991231, 12,	235959, 1),
			('SQLWATCH-INTERNAL-RETENTION',		4, 1, 8, 1,  0, 1, 20180101, 99991231, 20,	235959, 1),
			('SQLWATCH-LOGGER-DISK-UTILISATION',4, 1, 8, 1,  0, 1, 20180101, 99991231, 437,	235959, 1),
			('SQLWATCH-LOGGER-INDEXES',			4, 1, 8, 6,  0, 1, 20180101, 99991231, 420,	235959, 1),
			('SQLWATCH-INTERNAL-CONFIG',		4, 1, 8, 1,  0, 1, 20180101, 99991231, 26,  235959, 1)			

/* step definition */
insert into #steps
	values	('dbo.usp_sqlwatch_logger_whoisactive',		1, 'SQLWATCH-LOGGER-WHOISACTIVE',		'TSQL', 'exec dbo.usp_sqlwatch_logger_whoisactive'),

			('dbo.usp_sqlwatch_logger_performance',		1, 'SQLWATCH-LOGGER-PERFORMANCE',		'TSQL', 'exec dbo.usp_sqlwatch_logger_performance'),
			('dbo.usp_sqlwatch_logger_xes_waits',		2, 'SQLWATCH-LOGGER-PERFORMANCE',		'TSQL', 'exec dbo.usp_sqlwatch_logger_xes_waits'),
			('dbo.usp_sqlwatch_logger_xes_blockers',	3, 'SQLWATCH-LOGGER-PERFORMANCE',		'TSQL', 'exec dbo.usp_sqlwatch_logger_xes_blockers'),
			('dbo.usp_sqlwatch_logger_xes_diagnostics',	4, 'SQLWATCH-LOGGER-PERFORMANCE',		'TSQL', 'exec dbo.usp_sqlwatch_logger_xes_diagnostics'),

			('dbo.usp_sqlwatch_internal_retention',		1, 'SQLWATCH-INTERNAL-RETENTION',		'TSQL', 'exec dbo.usp_sqlwatch_internal_retention'),

			('dbo.usp_sqlwatch_logger_disk_utilisation',1, 'SQLWATCH-LOGGER-DISK-UTILISATION',	'TSQL', 'exec dbo.usp_sqlwatch_logger_disk_utilisation'),
			('Get-WMIObject Win32_Volume',		2, 'SQLWATCH-LOGGER-DISK-UTILISATION',	'PowerShell', N'[datetime]$snapshot_time = (Invoke-SqlCmd -ServerInstance "' + @server + '" -Database ' + '$(DatabaseName)' + ' -Query "select [snapshot_time]=max([snapshot_time]) 
from [dbo].[sqlwatch_logger_snapshot_header]
where snapshot_type_id = 2").snapshot_time

#https://msdn.microsoft.com/en-us/library/aa394515(v=vs.85).aspx
#driveType 3 = Local disk
Get-WMIObject Win32_Volume | ?{$_.DriveType -eq 3} | %{
    $VolumeName = $_.Name
    $VolumeLabel = $_.Label
    $FileSystem = $_.Filesystem
    $BlockSize = $_.BlockSize
    $FreeSpace = $_.Freespace
    $Capacity = $_.Capacity
    $SnapshotTime = Get-Date $snapshot_time -format "yyyy-MM-dd HH:mm:ss.fff"
    Invoke-SqlCmd -ServerInstance "' + @server + '" -Database ' + '$(DatabaseName)' + ' -Query "
     insert into [dbo].[sqlwatch_logger_disk_utilisation_volume](
            [volume_name]
           ,[volume_label]
           ,[volume_fs]
           ,[volume_block_size_bytes]
           ,[volume_free_space_bytes]
           ,[volume_total_space_bytes]
           ,[snapshot_type_id]
           ,[snapshot_time])
    values (''$VolumeName'',''$VolumeLabel'',''$FileSystem'',$BlockSize,$FreeSpace,$Capacity,2,''$SnapshotTime'')
    " 
}'),
			('dbo.usp_sqlwatch_logger_missing_indexes',		1, 'SQLWATCH-LOGGER-INDEXES',		'TSQL', 'exec dbo.usp_sqlwatch_logger_missing_indexes'),
			('dbo.usp_sqlwatch_logger_index_usage_stats',	2, 'SQLWATCH-LOGGER-INDEXES',		'TSQL', 'exec dbo.usp_sqlwatch_logger_index_usage_stats'),
			('dbo.usp_sqlwatch_internal_add_database',	1, 'SQLWATCH-INTERNAL-CONFIG',		'TSQL', 'exec dbo.usp_sqlwatch_internal_add_database')


/* create job and steps */
select @sql = replace(replace(convert(nvarchar(max),(select ' if (select name from msdb.dbo.sysjobs where name = ''' + job_name + ''') is null 
	begin
		exec msdb.dbo.sp_add_job @job_name=N''' + job_name + ''',  @category_name=N''' + @job_category + ''', @enabled=' + convert(char(1),job_enabled) + ',@description=''' + @job_description + ''';
		exec msdb.dbo.sp_add_jobserver @job_name=N''' + job_name + ''', @server_name = ''' + @server + ''';
		' + (select 
				' exec msdb.dbo.sp_add_jobstep @job_name=N''' + job_name + ''', @step_name=N''' + step_name + ''',@step_id= ' + convert(varchar(10),step_id) + ',@subsystem=N''' + step_subsystem + ''',@command=''' + replace(step_command,'''','''''') + ''',@on_success_action=' + case when ROW_NUMBER() over (partition by job_name order by step_id desc) = 1 then '1' else '3' end +', @on_fail_action=' + case when ROW_NUMBER() over (partition by job_name order by step_id desc) = 1 then '2' else '3' end + ', @database_name=''' + @database_name + ''''

			 from #steps 
			 where #steps.job_name = #jobs.job_name 
			 order by step_id asc
			 for xml path ('')) + '
		exec msdb.dbo.sp_update_job @job_name=N''' + job_name + ''', @start_step_id=1
		exec msdb.dbo.sp_add_jobschedule @job_name=N''' + job_name + ''', @name=N''' + job_name + ''', @enabled=1,@freq_type=' + convert(varchar(10),freq_type) + ',@freq_interval=' + convert(varchar(10),freq_interval) + ',@freq_subday_type=' + convert(varchar(10),freq_subday_type) + ',@freq_subday_interval=' + convert(varchar(10),freq_subday_interval) + ',@freq_relative_interval=' + convert(varchar(10),freq_relative_interval) + ',@freq_recurrence_factor=' + convert(varchar(10),freq_recurrence_factor) + ',@active_start_date=' + convert(varchar(10),active_start_date) + ',@active_end_date=' + convert(varchar(10),active_end_date) + ',@active_start_time=' + convert(varchar(10),active_start_time) + ',@active_end_time=' + convert(varchar(10),active_end_time) + ';
		Print ''Job ''''' + job_name + ''''' created.''
	end
else
	begin
		Print ''Job ''''' + job_name + ''''' not created becuase it already exists.''
	end;'
	from #jobs
	for xml path ('')
)),'&#x0D;',''),'&amp;#x0D;','')

print @sql
exec (@sql)
