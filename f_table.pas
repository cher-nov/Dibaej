unit f_table;

{$MODE OBJFPC}
{$LONGSTRINGS ON}

interface {════════════════════════════════════════════════════════════════════}

uses
  SysUtils, Classes,
  Forms, Controls, Dialogs, StdCtrls, CheckLst,
  SQLdb, db, DBGrids,
  f_edit, tables;

{ –=────────────────────────────────────────────────────────────────────────=– }
type { Table viewer form class ═══════════════════════════════════════════════ }

  { TTableForm }

  TTableForm = class( TForm )
  { interface controls }
    DBGrid              : TDBGrid;
    AddEntryBtn         : TButton;
    EraseEntryBtn       : TButton;
    CommitBtn           : TButton;
    RollbackBtn         : TButton;
    RefreshBtn          : TButton;

    FiltersBox          : TGroupBox;
      FiltersCList      : TCheckListBox;
      ColumnsCB         : TComboBox;
      OperationsCB      : TComboBox;
      ConstEdit         : TEdit;
      LogicCB           : TComboBox;
      AddFilterBtn      : TButton;
      ClearFiltersBtn   : TButton;
      FiltersCheck      : TCheckBox;
  { end of interface controls }

    SQLTransaction  : TSQLTransaction;
    SQLQuery        : TSQLQuery;
    DataSource      : TDataSource;

    procedure FormShow( Sender: TObject );
    procedure FormDestroy( Sender: TObject );
    procedure FormClose( Sender: TObject; var CloseAction: TCloseAction );

    procedure CommitBtnClick( Sender: TObject );
    procedure RollbackBtnClick( Sender: TObject );
    procedure RefreshBtnClick( Sender: TObject );
    procedure DBGridTitleClick( Column: TColumn );
    procedure DBGridDblClick( Sender: TObject );

    procedure AddFilterBtnClick( Sender: TObject );
    procedure ClearFiltersBtnClick( Sender: TObject );
    procedure FiltersCListClick( Sender: TObject );
    procedure FilterChange( Sender: TObject );

    procedure RemoteUpdate();
    procedure AddEntryBtnClick( Sender: TObject );
    procedure EraseEntryBtnClick( Sender: TObject );
    procedure SQLQueryAfterInsert( DataSet: TDataSet );
    procedure SQLQueryAfterDelete( DataSet: TDataSet );
    procedure DataSourceUpdateData( Sender: TObject );
    procedure DataSourceStateChange( Sender: TObject );
    procedure SQLQueryAfterPost( DataSet: TDataSet );

  private
    FFilters : TFilterContext;
    FSortIndex : Integer;
    FDescSort : Boolean;
    FDataEdited : Boolean;

    procedure Fetch( Soft: Boolean = False; CursPos: Integer = -1 );
    procedure UpdateFilter( Index: Integer );

    procedure AdjustControls();
    procedure SetDataEdited( Edited: Boolean );
    function dlgDiscardChanges(): Boolean;

  public
    { public declarations }
  end;

{ –=────────────────────────────────────────────────────────────────────────=– }

function ShowTableForm( Index: Integer; DBConnection: TSQLConnection ): Boolean;

var
  TableForm : array of TTableForm;

implementation {═══════════════════════════════════════════════════════════════}

{$R *.lfm}

//returns FALSE if form was already created, TRUE otherwise
function ShowTableForm( Index: Integer; DBConnection: TSQLConnection ): Boolean;
begin

  if Assigned( TableForm[Index] ) then begin
    TableForm[Index].ShowOnTop();
    Result := False;
  end else begin
    TableForm[Index] := TTableForm.Create( Application.MainForm );
    with TableForm[Index] do begin
      Tag := Index;
      SQLTransaction.DataBase := DBConnection;
      SQLQuery.DataBase := DBConnection;
      Show();
    end;
    Result := True;
  end;

end;

{ –=────────────────────────────────────────────────────────────────────────=– }
{ ═ TTableInfo ─────────────────────────────────────────────────────────────── }

//FormShow used as FormCreate to prepare form somehow before (see ShowTableForm)
procedure TTableForm.FormShow( Sender: TObject );
begin
  Caption := RegTable[Tag].Caption;
  FSortIndex := -1;
  FDescSort := True; //will be set to FALSE on first sorting
  FDataEdited := False;

  FFilters := TFilterContext.Create( Tag );
  SQLTransaction.Active := True;
  Fetch();

  RegTable[Tag].GetColumns( ColumnsCB.Items );
  ColumnsCB.ItemIndex := 0;
  OperationsCB.Items.AddStrings( FilterOperations );
  OperationsCB.ItemIndex := 0;
  LogicCB.Items.AddStrings( FilterLogic );
  LogicCB.ItemIndex := 0;
end;

procedure TTableForm.FormDestroy( Sender: TObject );
begin
  FFilters.Destroy();
  TableForm[Tag] := nil;
end;

procedure TTableForm.FormClose( Sender: TObject; var CloseAction: TCloseAction );
begin
  if dlgDiscardChanges() then begin
    SQLTransaction.Rollback();
    CloseAction := caFree;
  end else begin
    CloseAction := TCloseAction.caNone; //caNone is also a transaction state
  end;
end;

{ COMMON INTERFACE PROCESSING ════════════════════════════════════════════════ }

procedure TTableForm.CommitBtnClick( Sender: TObject );
var
  cur : Integer;
begin
  cur := SQLQuery.RecNo;
  SQLTransaction.Commit();
  SetDataEdited( False );
  Fetch( False, cur );
end;

procedure TTableForm.RollbackBtnClick( Sender: TObject );
var
  cur : Integer;
begin
  cur := SQLQuery.RecNo;
  SQLTransaction.Rollback();
  SetDataEdited( False );
  Fetch( False, cur );
end;

procedure TTableForm.RefreshBtnClick( Sender: TObject );
begin
  Fetch();
end;

procedure TTableForm.DBGridTitleClick( Column: TColumn );
begin
  FSortIndex := Column.Index+1;
  FDescSort := not FDescSort;
  Fetch();
end;

procedure TTableForm.DBGridDblClick( Sender: TObject );
begin
  if DBGrid.ReadOnly and not SQLQuery.IsEmpty then
    ShowEditForm( Tag, SQLQuery.Fields, SQLTransaction );
end;

{ FILTERS PROCESSING ═════════════════════════════════════════════════════════ }

procedure TTableForm.AddFilterBtnClick( Sender: TObject );
begin
  FFilters.Add();
  FiltersCList.Items.Add('');
  FiltersCList.ItemIndex := FiltersCList.Count-1;
  FiltersCList.Checked[ FiltersCList.ItemIndex ] := True;
  UpdateFilter( FiltersCList.ItemIndex );
end;

procedure TTableForm.ClearFiltersBtnClick( Sender: TObject );
begin
  FiltersCList.Clear();
  FFilters.Clear();
end;

procedure TTableForm.FilterChange( Sender: TObject );
begin
  UpdateFilter( FiltersCList.ItemIndex );
end;

procedure TTableForm.FiltersCListClick( Sender: TObject );
begin
  if ( FiltersCList.ItemIndex < 0 ) then Exit;

  //to prevent updating on fields changing
  FiltersCList.Enabled := False;

  with FFilters.GetFilter( FiltersCList.ItemIndex ) do begin
    ColumnsCB.ItemIndex := Column;
    OperationsCB.ItemIndex := Operation;
    ConstEdit.Text := Constant;
    LogicCB.ItemIndex := Logic;
  end;

  FiltersCList.Enabled := True;
end;

procedure TTableForm.UpdateFilter( Index: Integer );
begin
  if not FiltersCList.Enabled or ( Index < 0 ) then Exit;
  FFilters.Update( Index, ColumnsCB.ItemIndex, OperationsCB.ItemIndex,
    ConstEdit.Text, LogicCB.ItemIndex );
  FiltersCList.Items.Strings[Index] := FFilters.GetSQL( Index, False );
end;

{ DATABASE EDITING ROUTINES ══════════════════════════════════════════════════ }

procedure TTableForm.RemoteUpdate();
begin
  Fetch( True );
  SetDataEdited( True );
end;

procedure TTableForm.AddEntryBtnClick( Sender: TObject );
begin
  if DBGrid.ReadOnly then
    ShowEditForm( Tag, nil, SQLTransaction )
  else
    SQLQuery.Append();
end;

procedure TTableForm.EraseEntryBtnClick( Sender: TObject );
var
  cur, id : Integer;
begin
  if SQLQuery.IsEmpty then Exit;

  if DBGrid.ReadOnly then begin
    cur := SQLQuery.RecNo;
    id := SQLQuery.Fields.Fields[ RegTable[Tag].KeyColumn ].AsInteger;

    SQLQuery.Active := False;
    SQLQuery.SQL.Text := RegTable[Tag].GetDeleteSQL();
    SQLQuery.ParamByName('0').AsInteger := id;

    SQLQuery.ExecSQL();
    Fetch( False, cur );
    SetDataEdited( True );
  end else
    SQLQuery.Delete();
end;

function TTableForm.dlgDiscardChanges(): Boolean;
begin
  if FDataEdited then
    Result := MessageDlg( 'There are some uncommited changes, discard?',
                          mtConfirmation, mbYesNo, 0 ) = mrYes
  else
    Result := True;
end;

procedure TTableForm.SetDataEdited( Edited: Boolean );
begin
  FDataEdited := Edited;
  CommitBtn.Enabled := Edited;
  RollbackBtn.Enabled := Edited;
end;

//next events are used ONLY for editing of simple tables
procedure TTableForm.SQLQueryAfterInsert( DataSet: TDataSet );
    begin AddEntryBtn.Enabled := False;
      end;

procedure TTableForm.SQLQueryAfterDelete( DataSet: TDataSet );
begin
  SQLQuery.ApplyUpdates();
  SetDataEdited( True );
end;

procedure TTableForm.DataSourceUpdateData( Sender: TObject );
    begin SetDataEdited( True );
      end;

procedure TTableForm.DataSourceStateChange( Sender: TObject );
    begin if ( DataSource.State = dsBrowse ) then AddEntryBtn.Enabled := True;
      end;

procedure TTableForm.SQLQueryAfterPost( DataSet: TDataSet );
    begin SQLQuery.ApplyUpdates();
      end;

{ DATABASE GRID FETCHING ROUTINES ════════════════════════════════════════════ }

procedure TTableForm.Fetch( Soft: Boolean = False; CursPos: Integer = -1 );
var
  QueryCmd : String;
  i, cur, param : Integer;
begin
  if ( CursPos = -1 ) then cur := SQLQuery.RecNo
                      else cur := CursPos;
  if Soft then
    SQLQuery.Refresh()

  else begin

    QueryCmd := '';
    if FiltersCheck.Checked then begin
      param := 0;
      for i := 0 to FiltersCList.Count-1 do begin
        if ( FiltersCList.Checked[i] ) then begin
          QueryCmd += ' ' + FFilters.GetSQL( i, True, QueryCmd <> '' ) + ':'
            + IntToStr(param);
          param += 1;
        end;
      end;
      if ( QueryCmd <> '' ) then
        QueryCmd := ' where' + QueryCmd;
    end;
  
    QueryCmd := RegTable[Tag].GetSelectSQL() + QueryCmd;
  
    if ( FSortIndex <> -1 ) then begin
      QueryCmd += ' order by ' + IntToStr( FSortIndex );
      if FDescSort then QueryCmd += ' desc';
    end;
  
    SQLQuery.Active := False;
    SQLQuery.SQL.Text := QueryCmd;
  
    if ( param > 0 ) then begin
      param := 0;
      for i := 0 to FiltersCList.Count-1 do begin
        if ( FiltersCList.Checked[i] ) then begin
          with SQLQuery.ParamByName( IntToStr(param) ) do begin
            AsString := FFilters.GetConst(i);
            if ( RegTable[Tag].Columns( FFilters.GetFilter(i).Column ).DataType = DT_NUMERIC ) then
              DataType := ftInteger;
          end;
          param += 1;
        end;
      end;
    end;

    SQLQuery.Active := True;

  end;

  SQLQuery.Last;
  SQLQuery.MoveBy( -(SQLQuery.RecNo-cur) );
  AdjustControls();
end;

procedure TTableForm.AdjustControls();
var
  i : Integer;
begin
  if not SQLQuery.CanModify then begin
    DBGrid.ReadOnly := True;
    DBGrid.Options := DBGrid.Options + [dgRowSelect] - [dgEditing];
  end;

  for i := 0 to RegTable[Tag].ColumnsNum-1 do
    with DBGrid.Columns.Items[i] do begin
      ReadOnly := i = RegTable[Self.Tag].KeyColumn;
      Field.Required := not ReadOnly;
      Title.Caption := RegTable[Self.Tag].ColumnCaption(i);
      if ( RegTable[Self.Tag].Columns(i).Width > 0 ) then
        Width := RegTable[Self.Tag].Columns(i).Width;
    end;
end;

end.

