USE MuOnline
GO
/****** Object:  StoredProcedure [dbo].[WZ_SetMasterResetInfo]    Script Date: 14/05/2023 12:27:33 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER Procedure [dbo].[WZ_SetMasterResetInfo] 
@Account varchar(10),
@Name varchar(10),
@Reset int,
@MasterReset int,
@MasterResetDay int,
@MasterResetWek int,
@MasterResetMon int
AS
BEGIN

SET NOCOUNT ON
SET XACT_ABORT ON

UPDATE Character SET ResetCount=@Reset,MasterResetCount=@MasterReset,MasterResetDay=@MasterResetDay,MasterResetWek=@MasterResetWek,MasterResetMon=@MasterResetMon WHERE AccountID=@Account AND Name=@Name

SET NOCOUNT OFF
SET XACT_ABORT OFF

END










