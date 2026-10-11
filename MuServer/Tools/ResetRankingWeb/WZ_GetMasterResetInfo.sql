USE MuOnline
GO
/****** Object:  StoredProcedure [dbo].[WZ_GetMasterResetInfo]    Script Date: 14/05/2023 12:27:42 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER Procedure [dbo].[WZ_GetMasterResetInfo]
@Account varchar(10),
@Name varchar(10)
AS
BEGIN

SET NOCOUNT ON
SET XACT_ABORT ON

DECLARE @MasterReset int
DECLARE @MasterResetDay int
DECLARE @MasterResetWek int
DECLARE @MasterResetMon int

SELECT @MasterReset=MasterResetCount,@MasterResetDay=MasterResetDay,@MasterResetWek=MasterResetWek,@MasterResetMon=MasterResetMon FROM Character WHERE AccountID=@Account AND Name=@Name

SELECT @MasterReset AS MasterReset,@MasterResetDay AS MasterResetDay,@MasterResetWek AS MasterResetWek,@MasterResetMon AS MasterResetMon

SET NOCOUNT OFF
SET XACT_ABORT OFF

END










