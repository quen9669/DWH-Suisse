"""
Générateur du projet SSIS DWH_Suisse_ETL (fichiers .dtsx, .conmgr, .params, .dtproj).

POURQUOI CE SCRIPT ?
    Les packages SSIS sont des fichiers XML très verbeux. Ils ont été produits
    par ce script pour garantir des noms, identifiants et conventions
    homogènes. Vous n'avez PAS besoin de l'exécuter : les fichiers générés
    sont déjà dans ssis/DWH_Suisse_ETL/.

    ATTENTION : si vous le relancez, il ÉCRASE les packages, y compris les
    modifications faites dans Visual Studio. Une fois le projet ouvert et
    modifié dans Visual Studio, c'est Visual Studio qui devient la référence.

Usage :  python tools/generate_ssis.py
"""
import base64
import os
import uuid
from xml.sax.saxutils import escape

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ssis", "DWH_Suisse_ETL")
PROJECT = "DWH_Suisse_ETL"
NS_UUID = uuid.UUID("6f1c2b8e-3d1a-4c55-9a51-2b7d8e0c4a10")
PRODUCT_VERSION = "16.0.5685.0"
CREATION_DATE = "10/27/2026 08:00:00"


def gid(*parts):
    """GUID déterministe (identique à chaque génération)."""
    return "{" + str(uuid.uuid5(NS_UUID, "|".join(parts))).upper() + "}"


def a(value):
    """Échappe une valeur d'attribut XML (guillemets et retours à la ligne inclus)."""
    return escape(str(value), {'"': "&quot;", "\n": "&#xA;", "\r": "&#xD;", "\t": "&#x9;"})


# --------------------------------------------------------------------------
# Paramètres de projet et connexions
# --------------------------------------------------------------------------
# TypeCode .NET : 3 = Boolean, 9 = Int32, 18 = String
PROJECT_PARAMS = [
    ("ServerName", 18, "localhost", "Instance SQL Server hébergeant CH_ADMIN, CH_ODS, CH_STG, CH_DWH"),
    ("DataFolder", 18, r"C:\DWH_Suisse\data", "Dossier racine des fichiers téléchargés"),
    ("ScriptsFolder", 18, r"C:\DWH_Suisse\DWH-Suisse\scripts", "Dossier des scripts PowerShell du dépôt"),
    ("NbJoursIstdaten", 9, "3", "Nombre de jours de passages réels à télécharger (les plus récents)"),
    ("RetentionJoursODS", 9, "30", "Durée de conservation des données brutes déjà intégrées"),
    ("TraiterCube", 3, "false", "true = traiter le cube SSAS en fin de chargement (après l'avoir déployé)"),
    ("ServeurSSAS", 18, "localhost", "Instance Analysis Services"),
    ("BaseSSAS", 18, "DWH_Suisse_Cube", "Nom du modèle tabulaire déployé"),
]

CONNECTIONS = {
    "CM_ADMIN": "CH_ADMIN",
    "CM_ODS": "CH_ODS",
    "CM_STG": "CH_STG",
    "CM_DWH": "CH_DWH",
}


def cm_id(name):
    return gid("conmgr", name)


def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(content)


def conmgr_xml(name, database):
    cs = (f"Data Source=localhost;Initial Catalog={database};Provider=MSOLEDBSQL.1;"
          f"Integrated Security=SSPI;Application Name=DWH_Suisse_ETL;Auto Translate=False;")
    return f'''<?xml version="1.0"?>
<DTS:ConnectionManager xmlns:DTS="www.microsoft.com/SqlServer/Dts"
  DTS:ObjectName="{name}"
  DTS:DTSID="{cm_id(name)}"
  DTS:CreationName="OLEDB">
  <DTS:PropertyExpression
    DTS:Name="ServerName">@[$Project::ServerName]</DTS:PropertyExpression>
  <DTS:ObjectData>
    <DTS:ConnectionManager
      DTS:ConnectionString="{a(cs)}" />
  </DTS:ObjectData>
</DTS:ConnectionManager>
'''


def param_props_xml(pid, value, dtype, desc, indent):
    sp = " " * indent
    return (f'{sp}<SSIS:Properties>\n'
            f'{sp}  <SSIS:Property SSIS:Name="ID">{pid}</SSIS:Property>\n'
            f'{sp}  <SSIS:Property SSIS:Name="CreationName"></SSIS:Property>\n'
            f'{sp}  <SSIS:Property SSIS:Name="Description">{escape(desc)}</SSIS:Property>\n'
            f'{sp}  <SSIS:Property SSIS:Name="IncludeInDebugDump">0</SSIS:Property>\n'
            f'{sp}  <SSIS:Property SSIS:Name="Required">0</SSIS:Property>\n'
            f'{sp}  <SSIS:Property SSIS:Name="Sensitive">0</SSIS:Property>\n'
            f'{sp}  <SSIS:Property SSIS:Name="Value">{escape(value)}</SSIS:Property>\n'
            f'{sp}  <SSIS:Property SSIS:Name="DataType">{dtype}</SSIS:Property>\n'
            f'{sp}</SSIS:Properties>\n')


def project_params_xml():
    body = ""
    for name, dtype, value, desc in PROJECT_PARAMS:
        body += f'  <SSIS:Parameter\n    SSIS:Name="{name}">\n'
        body += param_props_xml(gid("projparam", name), value, dtype, desc, 4)
        body += "  </SSIS:Parameter>\n"
    return ('<?xml version="1.0"?>\n<SSIS:Parameters xmlns:SSIS="www.microsoft.com/SqlServer/SSIS">\n'
            + body + "</SSIS:Parameters>\n")


# --------------------------------------------------------------------------
# Briques de base des packages
# --------------------------------------------------------------------------
class Pkg:
    """Contexte d'un package : nom, variables, chemin des objets."""

    def __init__(self, name, description, has_batch_param=True):
        self.name = name
        self.description = description
        self.has_batch_param = has_batch_param
        self.variables = []          # (name, vartype, value, expression)
        self.connections = []        # XML des connexions propres au package
        self.executables = []        # XML
        self.constraints = []        # XML
        self.event_handlers = ""     # XML
        self.n_constraints = 0

    def var(self, name, vartype, value, expression=None):
        self.variables.append((name, vartype, value, expression))

    def batch_ref(self):
        return "$Package::BatchId" if self.has_batch_param else "User::BatchId"


def constraint(pkg, container_path, from_path, to_path, value=0, logical_and=True):
    pkg.n_constraints += 1
    name = f"Constraint {pkg.n_constraints}"
    v = f'\n  DTS:Value="{value}"' if value else ""
    return f'''<DTS:PrecedenceConstraint
  DTS:refId="{a(container_path)}.PrecedenceConstraints[{name}]"
  DTS:CreationName=""
  DTS:DTSID="{gid(pkg.name, container_path, name)}"
  DTS:From="{a(from_path)}"
  DTS:LogicalAnd="{'True' if logical_and else 'False'}"
  DTS:ObjectName="{name}"
  DTS:To="{a(to_path)}"{v} />'''


def chain(pkg, container_path, paths):
    """Relie une liste d'exécutables en séquence (succès -> suivant)."""
    return [constraint(pkg, container_path, paths[i], paths[i + 1]) for i in range(len(paths) - 1)]


# Types OLE DB pour les paramètres de l'Execute SQL Task
LONG, NVARCHAR, BOOL = 3, 130, 11


def sql_task(pkg, path, conn, sql, params=(), result=None, description="", expressions=()):
    """Execute SQL Task. params = [(variable, type_oledb)], result = variable (ligne unique)."""
    name = path.split("\\")[-1]
    rs = '\n      SQLTask:ResultSetType="ResultSetType_SingleRow"' if result else ""
    inner = ""
    if result:
        inner += f'\n      <SQLTask:ResultBinding\n        SQLTask:ResultName="0"\n        SQLTask:DtsVariableName="{result}" />'
    for i, (variable, oledb_type) in enumerate(params):
        inner += (f'\n      <SQLTask:ParameterBinding\n        SQLTask:ParameterName="{i}"'
                  f'\n        SQLTask:DtsVariableName="{variable}"'
                  f'\n        SQLTask:ParameterDirection="Input"'
                  f'\n        SQLTask:DataType="{oledb_type}"'
                  f'\n        SQLTask:ParameterSize="-1" />')
    pe = "".join(f'\n  <DTS:PropertyExpression\n    DTS:Name="{n}">{escape(e)}</DTS:PropertyExpression>'
                 for n, e in expressions)
    return f'''<DTS:Executable
  DTS:refId="{a(path)}"
  DTS:CreationName="Microsoft.ExecuteSQLTask"
  DTS:Description="{a(description or 'Execute SQL Task')}"
  DTS:DTSID="{gid(pkg.name, path)}"
  DTS:ExecutableType="Microsoft.ExecuteSQLTask"
  DTS:LocaleID="-1"
  DTS:ObjectName="{a(name)}"
  DTS:TaskContact="Execute SQL Task; Microsoft Corporation; SQL Server 2022; © 2022 Microsoft Corporation; All Rights Reserved;http://www.microsoft.com/sql/support/default.asp;1"
  DTS:ThreadHint="0">{pe}
  <DTS:Variables />
  <DTS:ObjectData>
    <SQLTask:SqlTaskData
      SQLTask:Connection="{cm_id(conn)}"
      SQLTask:SqlStatementSource="{a(sql)}"{rs} xmlns:SQLTask="www.microsoft.com/sqlserver/dts/tasks/sqltask">{inner}
    </SQLTask:SqlTaskData>
  </DTS:ObjectData>
</DTS:Executable>'''


def process_task(pkg, path, arguments_expr, description):
    """Execute Process Task qui lance un script PowerShell du dépôt."""
    name = path.split("\\")[-1]
    exe = r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    return f'''<DTS:Executable
  DTS:refId="{a(path)}"
  DTS:CreationName="Microsoft.ExecuteProcess"
  DTS:Description="{a(description)}"
  DTS:DTSID="{gid(pkg.name, path)}"
  DTS:ExecutableType="Microsoft.ExecuteProcess"
  DTS:LocaleID="-1"
  DTS:ObjectName="{a(name)}"
  DTS:TaskContact="Execute Process Task;Microsoft Corporation; SQL Server 2022; © 2022 Microsoft Corporation; All Rights Reserved;http://www.microsoft.com/sql/support/default.asp;1"
  DTS:ThreadHint="0">
  <DTS:PropertyExpression
    DTS:Name="Arguments">{escape(arguments_expr)}</DTS:PropertyExpression>
  <DTS:Variables />
  <DTS:ObjectData>
    <ExecuteProcessData
      Executable="{a(exe)}"
      Arguments=""
      WindowStyle="Hidden"
      StandardOutputVariable="User::ProcessOutput" />
  </DTS:ObjectData>
</DTS:Executable>'''


def ps_args(script, extra):
    """Expression SSIS construisant les arguments de powershell.exe."""
    return ('"-NoProfile -ExecutionPolicy Bypass -File \\"" + @[$Project::ScriptsFolder] + "\\\\' + script
            + '\\" " + ' + extra)


def package_task(pkg, path, child, description):
    """Execute Package Task (référence de projet) ; transmet le BatchId."""
    name = path.split("\\")[-1]
    return f'''<DTS:Executable
  DTS:refId="{a(path)}"
  DTS:CreationName="Microsoft.ExecutePackageTask"
  DTS:Description="{a(description)}"
  DTS:DTSID="{gid(pkg.name, path)}"
  DTS:ExecutableType="Microsoft.ExecutePackageTask"
  DTS:LocaleID="-1"
  DTS:ObjectName="{a(name)}"
  DTS:TaskContact="Microsoft Corporation; Microsoft SQL Server; Microsoft Corporation; All Rights Reserved;http://www.microsoft.com/sql/support/default.asp;1">
  <DTS:Variables />
  <DTS:ObjectData>
    <ExecutePackageTask>
      <UseProjectReference>True</UseProjectReference>
      <PackageName>{escape(child)}.dtsx</PackageName>
      <ParameterAssignment>
        <ParameterName>BatchId</ParameterName>
        <BindedVariableOrParameterName>User::BatchId</BindedVariableOrParameterName>
      </ParameterAssignment>
    </ExecutePackageTask>
  </DTS:ObjectData>
</DTS:Executable>'''


def with_disable_expression(xml, expression):
    """Ajoute une expression sur la propriété Disable d'un exécutable."""
    marker = "\n  <DTS:Variables />"
    return xml.replace(marker, f'\n  <DTS:PropertyExpression\n    DTS:Name="Disable">{escape(expression)}</DTS:PropertyExpression>' + marker, 1)


def file_move_task(pkg, path, dest_var, description):
    name = path.split("\\")[-1]
    return f'''<DTS:Executable
  DTS:refId="{a(path)}"
  DTS:CreationName="Microsoft.FileSystemTask"
  DTS:Description="{a(description)}"
  DTS:DTSID="{gid(pkg.name, path)}"
  DTS:ExecutableType="Microsoft.FileSystemTask"
  DTS:LocaleID="-1"
  DTS:ObjectName="{a(name)}"
  DTS:TaskContact="File System Task;Microsoft Corporation; SQL Server 2022; © 2022 Microsoft Corporation; All Rights Reserved;http://www.microsoft.com/sql/support/default.asp;1"
  DTS:ThreadHint="0">
  <DTS:Variables />
  <DTS:ObjectData>
    <FileSystemData
      TaskOperationType="MoveFile"
      TaskOverwriteDestFile="True"
      TaskSourcePath="User::FilePath"
      TaskIsSourceVariable="True"
      TaskDestinationPath="{dest_var}"
      TaskIsDestinationVariable="True" />
  </DTS:ObjectData>
</DTS:Executable>'''


def sequence(pkg, path, children, constraints, description):
    name = path.split("\\")[-1]
    pc = ""
    if constraints:
        pc = "\n  <DTS:PrecedenceConstraints>\n" + indent("\n".join(constraints), 4) + "\n  </DTS:PrecedenceConstraints>"
    return f'''<DTS:Executable
  DTS:refId="{a(path)}"
  DTS:CreationName="STOCK:SEQUENCE"
  DTS:Description="{a(description)}"
  DTS:DTSID="{gid(pkg.name, path)}"
  DTS:ExecutableType="STOCK:SEQUENCE"
  DTS:LocaleID="-1"
  DTS:ObjectName="{a(name)}">
  <DTS:Variables />
  <DTS:Executables>
{indent(chr(10).join(children), 4)}
  </DTS:Executables>{pc}
</DTS:Executable>'''


def foreach_files(pkg, path, folder_expr, default_folder, filespec, children, constraints, description):
    name = path.split("\\")[-1]
    pc = ""
    if constraints:
        pc = "\n  <DTS:PrecedenceConstraints>\n" + indent("\n".join(constraints), 4) + "\n  </DTS:PrecedenceConstraints>"
    return f'''<DTS:Executable
  DTS:refId="{a(path)}"
  DTS:CreationName="STOCK:FOREACHLOOP"
  DTS:Description="{a(description)}"
  DTS:DTSID="{gid(pkg.name, path)}"
  DTS:ExecutableType="STOCK:FOREACHLOOP"
  DTS:LocaleID="-1"
  DTS:ObjectName="{a(name)}">
  <DTS:ForEachEnumerator
    DTS:CreationName="Microsoft.ForEachFileEnumerator"
    DTS:DTSID="{gid(pkg.name, path, 'enum')}"
    DTS:ObjectName="{gid(pkg.name, path, 'enumname')}">
    <DTS:PropertyExpression
      DTS:Name="Directory">{escape(folder_expr)}</DTS:PropertyExpression>
    <DTS:ObjectData>
      <ForEachFileEnumeratorProperties>
        <FEFEProperty
          Folder="{a(default_folder)}" />
        <FEFEProperty
          FileSpec="{a(filespec)}" />
        <FEFEProperty
          FileNameRetrievalType="0" />
        <FEFEProperty
          Recurse="0" />
      </ForEachFileEnumeratorProperties>
    </DTS:ObjectData>
  </DTS:ForEachEnumerator>
  <DTS:Variables />
  <DTS:Executables>
{indent(chr(10).join(children), 4)}
  </DTS:Executables>{pc}
  <DTS:ForEachVariableMappings>
    <DTS:ForEachVariableMapping
      DTS:CreationName=""
      DTS:DTSID="{gid(pkg.name, path, 'map')}"
      DTS:ObjectName="{gid(pkg.name, path, 'mapname')}"
      DTS:ValueIndex="0"
      DTS:VariableName="User::FilePath" />
  </DTS:ForEachVariableMappings>
</DTS:Executable>'''


def indent(text, n):
    sp = " " * n
    return "\n".join(sp + line if line else line for line in text.split("\n"))


# --------------------------------------------------------------------------
# Data Flow : fichier plat -> colonnes d'audit -> comptage -> table ODS
# --------------------------------------------------------------------------
def flatfile_connection(pkg, name, columns, conn_expr, default_path):
    cols = []
    for i, (col, width) in enumerate(columns):
        delim = "_x000A_" if i == len(columns) - 1 else "_x003B_"   # LF en fin de ligne, sinon ";"
        cols.append(f'''<DTS:FlatFileColumn
  DTS:ColumnType="Delimited"
  DTS:ColumnDelimiter="{delim}"
  DTS:MaximumWidth="{width}"
  DTS:DataType="130"
  DTS:TextQualified="True"
  DTS:ObjectName="{a(col)}"
  DTS:DTSID="{gid(pkg.name, name, col)}"
  DTS:CreationName="" />''')
    pkg.connections.append(f'''<DTS:ConnectionManager
  DTS:refId="Package.ConnectionManagers[{a(name)}]"
  DTS:CreationName="FLATFILE"
  DTS:DelayValidation="True"
  DTS:DTSID="{gid(pkg.name, 'ffcm', name)}"
  DTS:ObjectName="{a(name)}">
  <DTS:PropertyExpression
    DTS:Name="ConnectionString">{escape(conn_expr)}</DTS:PropertyExpression>
  <DTS:ObjectData>
    <DTS:ConnectionManager
      DTS:Format="Delimited"
      DTS:LocaleID="1033"
      DTS:HeaderRowDelimiter="_x000A_"
      DTS:ColumnNamesInFirstDataRow="True"
      DTS:RowDelimiter=""
      DTS:TextQualifier="_x003C_none_x003E_"
      DTS:CodePage="65001"
      DTS:ConnectionString="{a(default_path)}">
      <DTS:FlatFileColumns>
{indent(chr(10).join(cols), 8)}
      </DTS:FlatFileColumns>
    </DTS:ConnectionManager>
  </DTS:ObjectData>
</DTS:ConnectionManager>''')


def data_flow(pkg, path, ff_name, columns, dest_conn, dest_table, filename_var, description):
    """Data Flow Task : Flat File Source -> Derived Column -> Row Count -> OLE DB Destination."""
    src = f"{path}\\FFS Fichier source"
    der = f"{path}\\DER Colonnes audit"
    cnt = f"{path}\\CNT Lignes"
    dst = f"{path}\\OLE_DST {dest_table}"
    so = f"{src}.Outputs[Flat File Source Output]"
    soe = f"{src}.Outputs[Flat File Source Error Output]"
    dout = f"{der}.Outputs[Derived Column Output]"
    dine = f"{der}.Inputs[Derived Column Input]"
    deo = f"{der}.Outputs[Derived Column Error Output]"
    cin = f"{cnt}.Inputs[Row Count Input 1]"
    cout = f"{cnt}.Outputs[Row Count Output 1]"
    din = f"{dst}.Inputs[OLE DB Destination Input]"
    deout = f"{dst}.Outputs[OLE DB Destination Error Output]"

    def ff_col(col, width):
        return f'''<outputColumn
  refId="{a(so)}.Columns[{a(col)}]"
  dataType="wstr"
  errorOrTruncationOperation="Conversion"
  errorRowDisposition="FailComponent"
  externalMetadataColumnId="{a(so)}.ExternalColumns[{a(col)}]"
  length="{width}"
  lineageId="{a(so)}.Columns[{a(col)}]"
  name="{a(col)}"
  truncationRowDisposition="FailComponent">
  <properties>
    <property
      dataType="System.Boolean"
      description="Indicates whether the column uses the faster, locale-neutral parsing routines."
      name="FastParse">false</property>
    <property
      dataType="System.Boolean"
      description="Indicates whether the data is in binary format."
      name="UseBinaryFormat">false</property>
  </properties>
</outputColumn>'''

    out_cols = "\n".join(ff_col(c, w) for c, w in columns)
    ext_cols = "\n".join(
        f'<externalMetadataColumn\n  refId="{a(so)}.ExternalColumns[{a(c)}]"\n  dataType="wstr"\n  length="{w}"\n  name="{a(c)}" />'
        for c, w in columns)

    def err_cols(base, with_text=False):
        x = ""
        if with_text:
            x += (f'<outputColumn\n  refId="{a(base)}.Columns[Flat File Source Error Output Column]"\n  codePage="65001"\n'
                  f'  dataType="text"\n  description="Flat File Source Error Output Column"\n'
                  f'  lineageId="{a(base)}.Columns[Flat File Source Error Output Column]"\n'
                  f'  name="Flat File Source Error Output Column" />\n')
        x += (f'<outputColumn\n  refId="{a(base)}.Columns[ErrorCode]"\n  dataType="i4"\n'
              f'  lineageId="{a(base)}.Columns[ErrorCode]"\n  name="ErrorCode"\n  specialFlags="1" />\n'
              f'<outputColumn\n  refId="{a(base)}.Columns[ErrorColumn]"\n  dataType="i4"\n'
              f'  lineageId="{a(base)}.Columns[ErrorColumn]"\n  name="ErrorColumn"\n  specialFlags="2" />')
        return x

    source = f'''<component
  refId="{a(src)}"
  componentClassID="Microsoft.FlatFileSource"
  contactInfo="Flat File Source;Microsoft Corporation; Microsoft SQL Server; (C) Microsoft Corporation; All Rights Reserved; http://www.microsoft.com/sql/support;1"
  description="Flat File Source"
  localeId="1033"
  name="FFS Fichier source"
  usesDispositions="true"
  version="1">
  <properties>
    <property
      dataType="System.Boolean"
      description="Specifies whether zero-length columns are treated as null."
      name="RetainNulls">true</property>
    <property
      dataType="System.String"
      description="Specifies the name of an output column containing the file name. If no name is specified, no output column containing the file name will be generated."
      name="FileNameColumnName"></property>
  </properties>
  <connections>
    <connection
      refId="{a(src)}.Connections[FlatFileConnection]"
      connectionManagerID="Package.ConnectionManagers[{a(ff_name)}]"
      connectionManagerRefId="Package.ConnectionManagers[{a(ff_name)}]"
      name="FlatFileConnection" />
  </connections>
  <outputs>
    <output
      refId="{a(so)}"
      name="Flat File Source Output">
      <outputColumns>
{indent(out_cols, 8)}
      </outputColumns>
      <externalMetadataColumns
        isUsed="True">
{indent(ext_cols, 8)}
      </externalMetadataColumns>
    </output>
    <output
      refId="{a(soe)}"
      isErrorOut="true"
      name="Flat File Source Error Output">
      <outputColumns>
{indent(err_cols(soe, True), 8)}
      </outputColumns>
      <externalMetadataColumns />
    </output>
  </outputs>
</component>'''

    derived_defs = [
        ("_BatchId", "i4", None, f"@[{pkg.batch_ref()}]"),
        ("_SourceFile", "wstr", 260, f"(DT_WSTR,260)@[{filename_var}]"),
    ]
    der_cols = ""
    for col, dt, length, expr in derived_defs:
        ln = f'\n  length="{length}"' if length else ""
        der_cols += f'''<outputColumn
  refId="{a(dout)}.Columns[{col}]"
  dataType="{dt}"
  errorOrTruncationOperation="Computation"
  errorRowDisposition="FailComponent"{ln}
  lineageId="{a(dout)}.Columns[{col}]"
  name="{col}"
  truncationRowDisposition="FailComponent">
  <properties>
    <property
      containsID="true"
      dataType="System.String"
      description="Derived Column Expression"
      name="Expression">{escape(expr)}</property>
    <property
      containsID="true"
      dataType="System.String"
      description="Derived Column Friendly Expression"
      expressionType="Notify"
      name="FriendlyExpression">{escape(expr)}</property>
  </properties>
</outputColumn>
'''
    derived = f'''<component
  refId="{a(der)}"
  componentClassID="Microsoft.DerivedColumn"
  contactInfo="Derived Column;Microsoft Corporation; Microsoft SQL Server; (C) Microsoft Corporation; All Rights Reserved; http://www.microsoft.com/sql/support;0"
  description="Ajoute les colonnes d'audit : n° de lot et nom du fichier source"
  name="DER Colonnes audit"
  usesDispositions="true">
  <inputs>
    <input
      refId="{a(dine)}"
      description="Input to the Derived Column Transformation"
      name="Derived Column Input">
      <externalMetadataColumns />
    </input>
  </inputs>
  <outputs>
    <output
      refId="{a(dout)}"
      description="Default Output of the Derived Column Transformation"
      exclusionGroup="1"
      name="Derived Column Output"
      synchronousInputId="{a(dine)}">
      <outputColumns>
{indent(der_cols.rstrip(), 8)}
      </outputColumns>
      <externalMetadataColumns />
    </output>
    <output
      refId="{a(deo)}"
      description="Error Output of the Derived Column Transformation"
      exclusionGroup="1"
      isErrorOut="true"
      name="Derived Column Error Output"
      synchronousInputId="{a(dine)}">
      <outputColumns>
{indent(err_cols(deo), 8)}
      </outputColumns>
      <externalMetadataColumns />
    </output>
  </outputs>
</component>'''

    rowcount = f'''<component
  refId="{a(cnt)}"
  componentClassID="Microsoft.RowCount"
  contactInfo="Row Count;Microsoft Corporation; Microsoft SQL Server; (C) Microsoft Corporation; All Rights Reserved; http://www.microsoft.com/sql/support;0"
  description="Compte les lignes chargées (variable User::RowCount)"
  name="CNT Lignes">
  <properties>
    <property
      dataType="System.String"
      description="Specifies the variable to hold the row count."
      name="VariableName">User::RowCount</property>
  </properties>
  <inputs>
    <input
      refId="{a(cin)}"
      hasSideEffects="true"
      name="Row Count Input 1">
      <externalMetadataColumns />
    </input>
  </inputs>
  <outputs>
    <output
      refId="{a(cout)}"
      name="Row Count Output 1"
      synchronousInputId="{a(cin)}">
      <externalMetadataColumns />
    </output>
  </outputs>
</component>'''

    # Destination : colonnes source + colonnes d'audit
    mapped = [(c, "wstr", w, f"{so}.Columns[{c}]") for c, w in columns]
    mapped += [("_BatchId", "i4", None, f"{dout}.Columns[_BatchId]"),
               ("_SourceFile", "wstr", 260, f"{dout}.Columns[_SourceFile]")]
    in_cols, dst_ext = [], []
    for col, dt, length, lineage in mapped:
        cl = f'\n  cachedLength="{length}"' if length else ""
        ln = f'\n  length="{length}"' if length else ""
        in_cols.append(f'''<inputColumn
  refId="{a(din)}.Columns[{a(col)}]"
  cachedDataType="{dt}"{cl}
  cachedName="{a(col)}"
  externalMetadataColumnId="{a(din)}.ExternalColumns[{a(col)}]"
  lineageId="{a(lineage)}" />''')
        dst_ext.append(f'''<externalMetadataColumn
  refId="{a(din)}.ExternalColumns[{a(col)}]"
  dataType="{dt}"{ln}
  name="{a(col)}" />''')
    dst_ext.append(f'''<externalMetadataColumn
  refId="{a(din)}.ExternalColumns[_LoadDtm]"
  dataType="dbTimeStamp2"
  name="_LoadDtm"
  scale="0" />''')

    destination = f'''<component
  refId="{a(dst)}"
  componentClassID="Microsoft.OLEDBDestination"
  contactInfo="OLE DB Destination;Microsoft Corporation; Microsoft SQL Server; (C) Microsoft Corporation; All Rights Reserved; http://www.microsoft.com/sql/support;4"
  description="OLE DB Destination"
  name="OLE_DST {a(dest_table)}"
  usesDispositions="true"
  version="4">
  <properties>
    <property
      dataType="System.Int32"
      description="The number of seconds before a command times out.  A value of 0 indicates an infinite time-out."
      name="CommandTimeout">0</property>
    <property
      dataType="System.String"
      description="Specifies the name of the database object used to open a rowset."
      name="OpenRowset">{escape(dest_table)}</property>
    <property
      dataType="System.String"
      description="Specifies the variable that contains the name of the database object used to open a rowset."
      name="OpenRowsetVariable"></property>
    <property
      dataType="System.String"
      description="The SQL command to be executed."
      name="SqlCommand"
      UITypeEditor="Microsoft.DataTransformationServices.Controls.ModalMultilineStringEditor"></property>
    <property
      dataType="System.Int32"
      description="Specifies the column code page to use when code page information is unavailable from the data source."
      name="DefaultCodePage">1252</property>
    <property
      dataType="System.Boolean"
      description="Forces the use of the DefaultCodePage property value when describing character data."
      name="AlwaysUseDefaultCodePage">false</property>
    <property
      dataType="System.Int32"
      description="Specifies the mode used to access the database."
      name="AccessMode"
      typeConverter="AccessMode">3</property>
    <property
      dataType="System.Boolean"
      description="Indicates whether the values supplied for identity columns will be copied to the destination. If false, values for identity columns will be auto-generated at the destination. Applies only if fast load is turned on."
      name="FastLoadKeepIdentity">false</property>
    <property
      dataType="System.Boolean"
      description="Indicates whether the columns containing null will have null inserted in the destination. If false, columns containing null will have their default values inserted at the destination. Applies only if fast load is turned on."
      name="FastLoadKeepNulls">false</property>
    <property
      dataType="System.String"
      description="Specifies options to be used with fast load.  Applies only if fast load is turned on."
      name="FastLoadOptions">TABLOCK,CHECK_CONSTRAINTS</property>
    <property
      dataType="System.Int32"
      description="Specifies when commits are issued during data insertion.  A value of 0 specifies that one commit will be issued at the end of data insertion.  Applies only if fast load is turned on."
      name="FastLoadMaxInsertCommitSize">2147483647</property>
  </properties>
  <connections>
    <connection
      refId="{a(dst)}.Connections[OleDbConnection]"
      connectionManagerID="{cm_id(dest_conn)}:external"
      connectionManagerRefId="Project.ConnectionManagers[{dest_conn}]"
      description="The OLE DB runtime connection used to access the database."
      name="OleDbConnection" />
  </connections>
  <inputs>
    <input
      refId="{a(din)}"
      errorOrTruncationOperation="Insert"
      errorRowDisposition="FailComponent"
      hasSideEffects="true"
      name="OLE DB Destination Input">
      <inputColumns>
{indent(chr(10).join(in_cols), 8)}
      </inputColumns>
      <externalMetadataColumns
        isUsed="True">
{indent(chr(10).join(dst_ext), 8)}
      </externalMetadataColumns>
    </input>
  </inputs>
  <outputs>
    <output
      refId="{a(deout)}"
      exclusionGroup="1"
      isErrorOut="true"
      name="OLE DB Destination Error Output"
      synchronousInputId="{a(din)}">
      <outputColumns>
{indent(err_cols(deout), 8)}
      </outputColumns>
      <externalMetadataColumns />
    </output>
  </outputs>
</component>'''

    paths = f'''<path
  refId="{a(path)}.Paths[Flat File Source Output]"
  endId="{a(dine)}"
  name="Flat File Source Output"
  startId="{a(so)}" />
<path
  refId="{a(path)}.Paths[Derived Column Output]"
  endId="{a(cin)}"
  name="Derived Column Output"
  startId="{a(dout)}" />
<path
  refId="{a(path)}.Paths[Row Count Output 1]"
  endId="{a(din)}"
  name="Row Count Output 1"
  startId="{a(cout)}" />'''

    name = path.split("\\")[-1]
    return f'''<DTS:Executable
  DTS:refId="{a(path)}"
  DTS:CreationName="Microsoft.Pipeline"
  DTS:DelayValidation="True"
  DTS:Description="{a(description)}"
  DTS:DTSID="{gid(pkg.name, path)}"
  DTS:ExecutableType="Microsoft.Pipeline"
  DTS:LocaleID="-1"
  DTS:ObjectName="{a(name)}"
  DTS:TaskContact="Performs high-performance data extraction, transformation and loading;Microsoft Corporation; Microsoft SQL Server; (C) Microsoft Corporation; All Rights Reserved;http://www.microsoft.com/sql/support/default.asp;1">
  <DTS:Variables />
  <DTS:ObjectData>
    <pipeline
      version="1">
      <components>
{indent(source, 8)}
{indent(derived, 8)}
{indent(rowcount, 8)}
{indent(destination, 8)}
      </components>
      <paths>
{indent(paths, 8)}
      </paths>
    </pipeline>
  </DTS:ObjectData>
</DTS:Executable>'''


# --------------------------------------------------------------------------
# Assemblage d'un package
# --------------------------------------------------------------------------
VARTYPE = {"Int32": (3, "0"), "String": (8, ""), "Boolean": (11, "False")}


def package_xml(pkg):
    variables = []
    for name, vartype, value, expression in pkg.variables:
        code, default = VARTYPE[vartype]
        expr = ""
        if expression:
            expr = f'\n  DTS:EvaluateAsExpression="True"\n  DTS:Expression="{a(expression)}"'
        variables.append(f'''<DTS:Variable
  DTS:CreationName=""
  DTS:DTSID="{gid(pkg.name, 'var', name)}"{expr}
  DTS:IncludeInDebugDump="{'6789' if vartype == 'Boolean' else '2345'}"
  DTS:Namespace="User"
  DTS:ObjectName="{name}">
  <DTS:VariableValue
    DTS:DataType="{code}">{escape(value if value is not None else default)}</DTS:VariableValue>
</DTS:Variable>''')

    params = ""
    if pkg.has_batch_param:
        params = f'''
  <DTS:PackageParameters>
    <DTS:PackageParameter
      DTS:CreationName=""
      DTS:DataType="9"
      DTS:Description="N° du lot transmis par le master package (0 = exécution isolée)"
      DTS:DTSID="{gid(pkg.name, 'param', 'BatchId')}"
      DTS:ObjectName="BatchId">
      <DTS:Property
        DTS:DataType="3"
        DTS:Name="ParameterValue">0</DTS:Property>
    </DTS:PackageParameter>
  </DTS:PackageParameters>'''

    conns = ""
    if pkg.connections:
        conns = "\n  <DTS:ConnectionManagers>\n" + indent("\n".join(pkg.connections), 4) + "\n  </DTS:ConnectionManagers>"

    pcs = ""
    if pkg.constraints:
        pcs = "\n  <DTS:PrecedenceConstraints>\n" + indent("\n".join(pkg.constraints), 4) + "\n  </DTS:PrecedenceConstraints>"

    return f'''<?xml version="1.0"?>
<DTS:Executable xmlns:DTS="www.microsoft.com/SqlServer/Dts"
  DTS:refId="Package"
  DTS:CreationDate="{CREATION_DATE}"
  DTS:CreationName="Microsoft.Package"
  DTS:CreatorComputerName="DWH-SUISSE"
  DTS:CreatorName="DWH-SUISSE\\dev"
  DTS:Description="{a(pkg.description)}"
  DTS:DTSID="{gid(pkg.name, 'package')}"
  DTS:ExecutableType="Microsoft.Package"
  DTS:LastModifiedProductVersion="{PRODUCT_VERSION}"
  DTS:LocaleID="1033"
  DTS:ObjectName="{a(pkg.name)}"
  DTS:PackageType="5"
  DTS:ProtectionLevel="0"
  DTS:VersionBuild="1"
  DTS:VersionGUID="{gid(pkg.name, 'version')}">
  <DTS:Property
    DTS:Name="PackageFormatVersion">8</DTS:Property>{conns}{params}
  <DTS:Variables>
{indent(chr(10).join(variables), 4)}
  </DTS:Variables>
  <DTS:Executables>
{indent(chr(10).join(pkg.executables), 4)}
  </DTS:Executables>{pcs}{pkg.event_handlers}
</DTS:Executable>
'''


def on_error_handler(pkg, sql, params, conn="CM_ADMIN"):
    path = "Package.EventHandlers[OnError]"
    task = sql_task(pkg, f"{path}\\SQL Journaliser erreur", conn, sql, params,
                    description="Enregistre l'erreur dans CH_ADMIN")
    pkg.event_handlers = f'''
  <DTS:EventHandlers>
    <DTS:EventHandler
      DTS:refId="{path}"
      DTS:CreationName="OnError"
      DTS:DTSID="{gid(pkg.name, 'onerror')}"
      DTS:EventID="0"
      DTS:EventName="OnError"
      DTS:LocaleID="-1">
      <DTS:Variables>
        <DTS:Variable
          DTS:CreationName=""
          DTS:Description="The propagate property of the event"
          DTS:DTSID="{gid(pkg.name, 'onerror', 'propagate')}"
          DTS:IncludeInDebugDump="6789"
          DTS:Namespace="System"
          DTS:ObjectName="Propagate">
          <DTS:VariableValue
            DTS:DataType="11">-1</DTS:VariableValue>
        </DTS:Variable>
      </DTS:Variables>
      <DTS:Executables>
{indent(task, 8)}
      </DTS:Executables>
    </DTS:EventHandler>
  </DTS:EventHandlers>'''


def child_package(name, description, body_builder):
    """
    Modèle commun des packages enfants :
      SQL Début étape  ->  [corps]  ->  SQL Fin étape
      + gestionnaire OnError qui marque l'étape en échec.
    body_builder(pkg) renvoie (liste_exécutables, liste_contraintes, premier, dernier, sql_fin, params_fin)
    """
    pkg = Pkg(name, description)
    pkg.var("BatchId", "Int32", "0", "@[$Package::BatchId]")
    pkg.var("StepId", "Int32", "0")
    pkg.var("ProcessOutput", "String", "")

    start = "Package\\SQL Début étape"
    pkg.executables.append(sql_task(
        pkg, start, "CM_ADMIN", "EXEC etl.usp_Step_Start @BatchId = ?, @StepName = ?;",
        [("$Package::BatchId", LONG), ("System::PackageName", NVARCHAR)], result="User::StepId",
        description="Journalise le début du package dans CH_ADMIN.etl.StepLog"))

    execs, cons, first, last, end_sql, end_params = body_builder(pkg)
    pkg.executables.extend(execs)

    end = "Package\\SQL Fin étape"
    pkg.executables.append(sql_task(pkg, end, "CM_ADMIN", end_sql, end_params,
                                    description="Journalise la fin du package"))
    pkg.constraints.append(constraint(pkg, "Package", start, first))
    pkg.constraints.extend(cons)
    pkg.constraints.append(constraint(pkg, "Package", last, end))

    on_error_handler(pkg, "EXEC etl.usp_Step_End @StepId = ?, @Status = N'Échec', @Message = ?;",
                     [("User::StepId", LONG), ("System::ErrorDescription", NVARCHAR)])
    return pkg


STEP_END_SIMPLE = ("EXEC etl.usp_Step_End @StepId = ?, @Status = N'Succès';", [("User::StepId", LONG)])

# --------------------------------------------------------------------------
# Définition des colonnes des fichiers sources
# --------------------------------------------------------------------------
ISTDATEN_COLUMNS = [(c, 255) for c in (
    "BETRIEBSTAG FAHRT_BEZEICHNER BETREIBER_ID BETREIBER_ABK BETREIBER_NAME PRODUKT_ID LINIEN_ID "
    "LINIEN_TEXT UMLAUF_ID VERKEHRSMITTEL_TEXT ZUSATZFAHRT_TF FAELLT_AUS_TF BPUIC HALTESTELLEN_NAME "
    "ANKUNFTSZEIT AN_PROGNOSE AN_PROGNOSE_STATUS ABFAHRTSZEIT AB_PROGNOSE AB_PROGNOSE_STATUS "
    "DURCHFAHRT_TF SLOID").split()]

SERVICEPOINT_COLUMNS = [(c, 1000 if c == "fotComment" else 255) for c in (
    "numberShort uicCountryCode sloid number checkDigit validFrom validTo designationOfficial "
    "designationLong abbreviation operatingPoint operatingPointWithTimetable stopPoint stopPointType "
    "freightServicePoint trafficPoint borderPoint hasGeolocation isoCountryCode cantonName "
    "cantonFsoNumber cantonAbbreviation districtName districtFsoNumber municipalityName fsoNumber "
    "localityName operatingPointType operatingPointTechnicalTimetableType meansOfTransport categories "
    "operatingPointTrafficPointType operatingPointRouteNetwork operatingPointKilometer "
    "operatingPointKilometerMasterNumber sortCodeOfDestinationStation businessOrganisation "
    "businessOrganisationNumber businessOrganisationAbbreviationDe businessOrganisationAbbreviationFr "
    "businessOrganisationAbbreviationIt businessOrganisationAbbreviationEn "
    "businessOrganisationDescriptionDe businessOrganisationDescriptionFr "
    "businessOrganisationDescriptionIt businessOrganisationDescriptionEn fotComment lv95East "
    "lv95North wgs84East wgs84North height creationDate editionDate status").split()]
assert len(ISTDATEN_COLUMNS) == 22 and len(SERVICEPOINT_COLUMNS) == 55


# --------------------------------------------------------------------------
# Les packages
# --------------------------------------------------------------------------
def pkg_10_ext():
    def body(pkg):
        p1 = "Package\\EPT Référentiel des arrêts"
        p2 = "Package\\EPT Passages réels Istdaten"
        p3 = "Package\\EPT Météo Open-Meteo"
        df = '"-DataFolder \\"" + @[$Project::DataFolder] + "\\""'
        execs = [
            process_task(pkg, p1, ps_args("Get-ServicePoints.ps1", df),
                         "Télécharge le référentiel des points d'arrêt (scripts\\Get-ServicePoints.ps1)"),
            process_task(pkg, p2, ps_args("Get-Istdaten.ps1",
                                          df + ' + " -NbJours " + (DT_WSTR,5)@[$Project::NbJoursIstdaten]'),
                         "Télécharge les N derniers jours de passages réels (scripts\\Get-Istdaten.ps1)"),
            process_task(pkg, p3, ps_args("Get-Meteo.ps1", df),
                         "Télécharge la météo des jours reçus (scripts\\Get-Meteo.ps1)"),
        ]
        return execs, chain(pkg, "Package", [p1, p2, p3]), p1, p3, *STEP_END_SIMPLE
    return child_package("10_EXT_Telechargement",
                         "EXTRACTION : télécharge les fichiers sources (gares, passages réels, météo) via PowerShell.",
                         body)


def pkg_20_ods_servicepoints():
    def body(pkg):
        pkg.var("RowCount", "Int32", "0")
        pkg.var("FileName", "String", "service-points.csv")
        flatfile_connection(pkg, "FF ServicePoints", SERVICEPOINT_COLUMNS,
                            '@[$Project::DataFolder] + "\\\\servicepoints\\\\service-points.csv"',
                            r"C:\DWH_Suisse\data\servicepoints\service-points.csv")
        p1 = "Package\\SQL Vider ods ServicePoint"
        p2 = "Package\\DFT Charger ods ServicePoint"
        execs = [
            sql_task(pkg, p1, "CM_ODS", "TRUNCATE TABLE ods.ServicePoint;",
                     description="Le référentiel est une photo complète : on vide avant de recharger"),
            data_flow(pkg, p2, "FF ServicePoints", SERVICEPOINT_COLUMNS, "CM_ODS", "[ods].[ServicePoint]",
                      "User::FileName", "Fichier CSV -> CH_ODS.ods.ServicePoint (brut, tout en texte)"),
        ]
        end_sql = "EXEC etl.usp_Step_End @StepId = ?, @Status = N'Succès', @RowsInserted = ?;"
        return execs, chain(pkg, "Package", [p1, p2]), p1, p2, end_sql, [("User::StepId", LONG), ("User::RowCount", LONG)]
    return child_package("20_ODS_ServicePoints",
                         "ODS : charge le référentiel des points d'arrêt (CSV) dans CH_ODS.ods.ServicePoint.",
                         body)


def pkg_21_ods_istdaten():
    def body(pkg):
        pkg.var("RowCount", "Int32", "0")
        pkg.var("FilePath", "String", r"C:\DWH_Suisse\data\istdaten\exemple_istdaten.csv")
        pkg.var("FileName", "String", "", 'TOKEN(@[User::FilePath], "\\\\", TOKENCOUNT(@[User::FilePath], "\\\\"))')
        pkg.var("ArchiveFolder", "String", "", '@[$Project::DataFolder] + "\\\\archive\\\\istdaten"')
        flatfile_connection(pkg, "FF Istdaten", ISTDATEN_COLUMNS, "@[User::FilePath]",
                            r"C:\DWH_Suisse\data\istdaten\exemple_istdaten.csv")
        loop = "Package\\FEL Fichiers Istdaten"
        s1 = f"{loop}\\SQL Préparer fichier"
        s2 = f"{loop}\\DFT Charger ods Istdaten"
        s3 = f"{loop}\\SQL Enregistrer fichier"
        s4 = f"{loop}\\FST Archiver fichier"
        children = [
            sql_task(pkg, s1, "CM_ODS", "EXEC ods.usp_Istdaten_PrepareFile @SourceFile = ?;",
                     [("User::FileName", NVARCHAR)],
                     description="Supprime les lignes de ce fichier déjà présentes (reprise après incident)"),
            data_flow(pkg, s2, "FF Istdaten", ISTDATEN_COLUMNS, "CM_ODS", "[ods].[Istdaten]",
                      "User::FileName", "Fichier CSV du jour -> CH_ODS.ods.Istdaten (brut, tout en texte)"),
            sql_task(pkg, s3, "CM_ADMIN",
                     "EXEC etl.usp_File_Register @SourceType = N'ISTDATEN', @FileName = ?, @BatchId = ?, @RowsOds = ?;",
                     [("User::FileName", NVARCHAR), ("User::BatchId", LONG), ("User::RowCount", LONG)],
                     description="Inscrit le fichier dans CH_ADMIN.etl.FileLog (statut ODS_OK)"),
            file_move_task(pkg, s4, "User::ArchiveFolder", "Déplace le fichier traité vers archive\\istdaten"),
        ]
        cons = chain(pkg, loop, [s1, s2, s3, s4])
        fel = foreach_files(pkg, loop, '@[$Project::DataFolder] + "\\\\istdaten"',
                            r"C:\DWH_Suisse\data\istdaten", "*_istdaten.csv", children, cons,
                            "Boucle sur chaque fichier Istdaten téléchargé")
        end_sql = "EXEC etl.usp_Step_End_Files @StepId = ?, @BatchId = ?, @SourceType = N'ISTDATEN';"
        return [fel], [], loop, loop, end_sql, [("User::StepId", LONG), ("User::BatchId", LONG)]
    return child_package("21_ODS_Istdaten",
                         "ODS : charge chaque fichier Istdaten (passages réels) dans CH_ODS.ods.Istdaten puis l'archive.",
                         body)


def pkg_22_ods_meteo():
    def body(pkg):
        pkg.var("FilePath", "String", r"C:\DWH_Suisse\data\meteo\exemple.json")
        pkg.var("ArchiveFolder", "String", "", '@[$Project::DataFolder] + "\\\\archive\\\\meteo"')
        loop = "Package\\FEL Fichiers météo"
        s1 = f"{loop}\\SQL Charger JSON"
        s2 = f"{loop}\\FST Archiver fichier"
        children = [
            sql_task(pkg, s1, "CM_ODS", "EXEC ods.usp_Load_MeteoJson @FilePath = ?, @BatchId = ?;",
                     [("User::FilePath", NVARCHAR), ("User::BatchId", LONG)],
                     description="SQL Server lit le JSON (OPENROWSET) et le stocke tel quel dans ods.MeteoJson"),
            file_move_task(pkg, s2, "User::ArchiveFolder", "Déplace le fichier traité vers archive\\meteo"),
        ]
        cons = chain(pkg, loop, [s1, s2])
        fel = foreach_files(pkg, loop, '@[$Project::DataFolder] + "\\\\meteo"',
                            r"C:\DWH_Suisse\data\meteo", "meteo_*.json", children, cons,
                            "Boucle sur chaque fichier météo JSON")
        end_sql = "EXEC etl.usp_Step_End_Files @StepId = ?, @BatchId = ?, @SourceType = N'METEO';"
        return [fel], [], loop, loop, end_sql, [("User::StepId", LONG), ("User::BatchId", LONG)]
    return child_package("22_ODS_Meteo",
                         "ODS : charge les réponses JSON d'Open-Meteo dans CH_ODS.ods.MeteoJson puis les archive.",
                         body)


def proc_package(name, description, conn, groups):
    """
    Package qui enchaîne des procédures stockées.
    groups = liste de groupes ; les procédures d'un même groupe tournent en PARALLÈLE
    (dans un conteneur de séquence), les groupes s'enchaînent en SÉRIE.
    """
    def body(pkg):
        execs, paths = [], []
        for gi, (label, procs) in enumerate(groups, 1):
            if len(procs) == 1:
                proc = procs[0]
                p = f"Package\\SQL {proc}"
                execs.append(sql_task(pkg, p, conn, f"EXEC {proc} @BatchId = ?;", [("User::BatchId", LONG)],
                                      description=f"Exécute {proc}"))
            else:
                p = f"Package\\SEQ {label}"
                children = [sql_task(pkg, f"{p}\\SQL {proc}", conn, f"EXEC {proc} @BatchId = ?;",
                                     [("User::BatchId", LONG)], description=f"Exécute {proc}") for proc in procs]
                execs.append(sequence(pkg, p, children, [],
                                      "Tâches indépendantes exécutées en parallèle"))
            paths.append(p)
        return execs, chain(pkg, "Package", paths), paths[0], paths[-1], *STEP_END_SIMPLE
    return child_package(name, description, body)


def pkg_50_ssas():
    def body(pkg):
        p = "Package\\EPT Traiter le cube"
        args = ps_args("Invoke-ProcessCube.ps1",
                       '"-Server \\"" + @[$Project::ServeurSSAS] + "\\" -Database \\"" + @[$Project::BaseSSAS]'
                       ' + "\\" -DataFolder \\"" + @[$Project::DataFolder] + "\\""')
        execs = [process_task(pkg, p, args, "Recharge le modèle tabulaire SSAS (scripts\\Invoke-ProcessCube.ps1)")]
        return execs, [], p, p, *STEP_END_SIMPLE
    return child_package("50_SSAS_Traitement",
                         "CUBE : traite (recharge) le modèle SSAS Tabular depuis CH_DWH.", body)


def pkg_00_master():
    pkg = Pkg("00_MASTER",
              "MASTER PACKAGE : orchestre tout le chargement (extraction > ODS > STG > DWH > cube) "
              "et journalise le lot dans CH_ADMIN.", has_batch_param=False)
    pkg.var("BatchId", "Int32", "0")

    start = "Package\\SQL Ouvrir le lot"
    seq1 = "Package\\SEQ 1 Extraction"
    seq2 = "Package\\SEQ 2 ODS"
    seq3 = "Package\\SEQ 3 STG"
    seq4 = "Package\\SEQ 4 DWH"
    cube = "Package\\EPT 50_SSAS_Traitement"
    purge = "Package\\SQL Purger ODS"
    end = "Package\\SQL Clôturer le lot"

    def ept(container, child, desc):
        return package_task(pkg, f"{container}\\EPT {child}", child, desc)

    pkg.executables = [
        sql_task(pkg, start, "CM_ADMIN", "EXEC etl.usp_Batch_Start @PackageName = ?;",
                 [("System::PackageName", NVARCHAR)], result="User::BatchId",
                 description="Crée un nouveau lot dans CH_ADMIN.etl.Batch et récupère son n°"),
        sequence(pkg, seq1, [ept(seq1, "10_EXT_Telechargement", "Téléchargement des sources")], [],
                 "Étape 1 : récupérer les fichiers sources"),
        sequence(pkg, seq2, [
            ept(seq2, "20_ODS_ServicePoints", "Référentiel des arrêts -> ODS"),
            ept(seq2, "21_ODS_Istdaten", "Passages réels -> ODS"),
            ept(seq2, "22_ODS_Meteo", "Météo -> ODS"),
        ], [], "Étape 2 : charger les données brutes (3 packages en parallèle)"),
        sequence(pkg, seq3, [ept(seq3, "30_STG_Preparation", "Typage, qualité, calculs")], [],
                 "Étape 3 : préparer les données (staging)"),
        sequence(pkg, seq4, [
            ept(seq4, "40_DWH_Dimensions", "Dimensions"),
            ept(seq4, "41_DWH_Faits", "Faits"),
        ], [constraint(pkg, seq4, f"{seq4}\\EPT 40_DWH_Dimensions", f"{seq4}\\EPT 41_DWH_Faits")],
            "Étape 4 : alimenter l'entrepôt (dimensions PUIS faits)"),
        with_disable_expression(
            package_task(pkg, cube, "50_SSAS_Traitement",
                         "Étape 5 : traiter le cube (désactivé tant que le paramètre TraiterCube = false)"),
            "!@[$Project::TraiterCube]"),
        sql_task(pkg, purge, "CM_ODS", "EXEC ods.usp_Purge @BatchId = ?, @RetentionDays = ?;",
                 [("User::BatchId", LONG), ("$Project::RetentionJoursODS", LONG)],
                 description="Supprime les données brutes intégrées depuis plus de N jours"),
        sql_task(pkg, end, "CM_ADMIN", "EXEC etl.usp_Batch_End @BatchId = ?, @Status = N'Succès';",
                 [("User::BatchId", LONG)], description="Marque le lot en succès"),
    ]
    pkg.constraints = chain(pkg, "Package", [start, seq1, seq2, seq3, seq4, cube, purge, end])
    on_error_handler(pkg,
                     "EXEC etl.usp_Batch_End @BatchId = ?, @Status = N'Échec', @ErrorMessage = ?, @SourceName = ?;",
                     [("User::BatchId", LONG), ("System::ErrorDescription", NVARCHAR), ("System::SourceName", NVARCHAR)])
    return pkg


def all_packages():
    return [
        pkg_00_master(),
        pkg_10_ext(),
        pkg_20_ods_servicepoints(),
        pkg_21_ods_istdaten(),
        pkg_22_ods_meteo(),
        proc_package("30_STG_Preparation",
                     "STG : convertit, contrôle et prépare les données brutes (procédures stg.*).",
                     "CM_STG",
                     [("Preparation", ["stg.usp_Load_ServicePoint", "stg.usp_Load_Istdaten", "stg.usp_Load_Meteo"])]),
        proc_package("40_DWH_Dimensions",
                     "DWH : alimente les dimensions (SCD1 opérateurs/lignes, SCD2 arrêts, membres déduits).",
                     "CM_DWH",
                     [("Dimensions simples", ["etl.usp_Load_DimOperator", "etl.usp_Load_DimTransportMode",
                                              "etl.usp_Load_DimLine"]),
                      ("Arrets", ["etl.usp_Load_DimStation"]),
                      ("Arrets deduits", ["etl.usp_Load_DimStation_Inferred"])]),
        proc_package("41_DWH_Faits",
                     "DWH : alimente les tables de faits (passages, météo) - suppression/insertion par jour.",
                     "CM_DWH",
                     [("Faits", ["etl.usp_Load_FactStopEvent", "etl.usp_Load_FactWeatherHourly"])]),
        pkg_50_ssas(),
    ]


# --------------------------------------------------------------------------
# Fichier projet .dtproj
# --------------------------------------------------------------------------
def dtproj_xml(packages):
    source_control = ('<SourceControlInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
                      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\r\n'
                      '  <Enabled>false</Enabled>\r\n  <ProjectName></ProjectName>\r\n'
                      '  <AuthenticationData></AuthenticationData>\r\n  <LogicalProjectName></LogicalProjectName>\r\n'
                      '  <SourceControlProvider></SourceControlProvider>\r\n</SourceControlInfo>')
    state = "$base64$" + base64.b64encode(source_control.encode("utf-8")).decode("ascii")

    pkg_list = "\n".join(f'          <SSIS:Package SSIS:Name="{p.name}.dtsx" SSIS:EntryPoint="1" />' for p in packages)
    cm_list = "\n".join(f'          <SSIS:ConnectionManager SSIS:Name="{n}.conmgr" />' for n in CONNECTIONS)

    meta = ""
    for p in packages:
        params = ""
        if p.has_batch_param:
            params = ("              <SSIS:Parameters>\n"
                      '                <SSIS:Parameter SSIS:Name="BatchId">\n'
                      + param_props_xml(gid(p.name, "param", "BatchId"), "0", 9,
                                        "N° du lot transmis par le master package (0 = exécution isolée)", 18)
                      + "                </SSIS:Parameter>\n              </SSIS:Parameters>\n")
        else:
            params = "              <SSIS:Parameters />\n"
        meta += f'''            <SSIS:PackageMetaData SSIS:Name="{p.name}.dtsx">
              <SSIS:Properties>
                <SSIS:Property SSIS:Name="ID">{gid(p.name, 'package')}</SSIS:Property>
                <SSIS:Property SSIS:Name="Name">{escape(p.name)}</SSIS:Property>
                <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
                <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
                <SSIS:Property SSIS:Name="VersionBuild">1</SSIS:Property>
                <SSIS:Property SSIS:Name="VersionComments"></SSIS:Property>
                <SSIS:Property SSIS:Name="VersionGUID">{gid(p.name, 'version')}</SSIS:Property>
                <SSIS:Property SSIS:Name="PackageFormatVersion">8</SSIS:Property>
                <SSIS:Property SSIS:Name="Description">{escape(p.description)}</SSIS:Property>
                <SSIS:Property SSIS:Name="ProtectionLevel">0</SSIS:Property>
              </SSIS:Properties>
{params}            </SSIS:PackageMetaData>
'''

    return f'''<?xml version="1.0" encoding="utf-8"?>
<Project xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <DeploymentModel>Project</DeploymentModel>
  <ProductVersion>{PRODUCT_VERSION}</ProductVersion>
  <SchemaVersion>9.0.1.0</SchemaVersion>
  <State>{state}</State>
  <Database>
    <Name>{PROJECT}.database</Name>
    <FullPath>{PROJECT}.database</FullPath>
  </Database>
  <DataSources />
  <DataSourceViews />
  <DeploymentModelSpecificContent>
    <Manifest>
      <SSIS:Project SSIS:ProtectionLevel="DontSaveSensitive" xmlns:SSIS="www.microsoft.com/SqlServer/SSIS">
        <SSIS:Properties>
          <SSIS:Property SSIS:Name="ID">{gid('project')}</SSIS:Property>
          <SSIS:Property SSIS:Name="Name">{PROJECT}</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMajor">1</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionMinor">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionBuild">0</SSIS:Property>
          <SSIS:Property SSIS:Name="VersionComments"></SSIS:Property>
          <SSIS:Property SSIS:Name="CreationDate">2026-10-27T08:00:00</SSIS:Property>
          <SSIS:Property SSIS:Name="CreatorName">DWH-SUISSE\\dev</SSIS:Property>
          <SSIS:Property SSIS:Name="CreatorComputerName">DWH-SUISSE</SSIS:Property>
          <SSIS:Property SSIS:Name="Description">Alimentation du DWH Suisse (transports publics + météo)</SSIS:Property>
          <SSIS:Property SSIS:Name="FormatVersion">1</SSIS:Property>
        </SSIS:Properties>
        <SSIS:Packages>
{pkg_list}
        </SSIS:Packages>
        <SSIS:ConnectionManagers>
{cm_list}
        </SSIS:ConnectionManagers>
        <SSIS:DeploymentInfo>
          <SSIS:ProjectConnectionParameters />
          <SSIS:PackageInfo>
{meta.rstrip()}
          </SSIS:PackageInfo>
        </SSIS:DeploymentInfo>
      </SSIS:Project>
    </Manifest>
  </DeploymentModelSpecificContent>
  <ControlFlowParts />
  <Miscellaneous />
  <Configurations>
    <Configuration>
      <Name>Development</Name>
      <Options>
        <OutputPath>bin</OutputPath>
        <ConnectionMappings />
        <ConnectionProviderMappings />
        <ConnectionSecurityMappings />
        <DatabaseStorageLocations />
        <TargetServerVersion>SQLServer2022</TargetServerVersion>
        <ParameterConfigurationValues />
      </Options>
    </Configuration>
  </Configurations>
</Project>
'''


DATABASE_XML = f'''<Database xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ddl2="http://schemas.microsoft.com/analysisservices/2003/engine/2" xmlns:ddl2_2="http://schemas.microsoft.com/analysisservices/2003/engine/2/2" xmlns:ddl100_100="http://schemas.microsoft.com/analysisservices/2008/engine/100/100" xmlns:ddl200="http://schemas.microsoft.com/analysisservices/2010/engine/200" xmlns:ddl200_200="http://schemas.microsoft.com/analysisservices/2010/engine/200/200" xmlns:ddl300="http://schemas.microsoft.com/analysisservices/2011/engine/300" xmlns:ddl300_300="http://schemas.microsoft.com/analysisservices/2011/engine/300/300" xmlns:ddl400="http://schemas.microsoft.com/analysisservices/2012/engine/400" xmlns:ddl400_400="http://schemas.microsoft.com/analysisservices/2012/engine/400/400" xmlns:ddl500="http://schemas.microsoft.com/analysisservices/2013/engine/500" xmlns:ddl500_500="http://schemas.microsoft.com/analysisservices/2013/engine/500/500" xmlns:dwd="http://schemas.microsoft.com/DataWarehouse/Designer/1.0" xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">
  <ID>{PROJECT}</ID>
  <Name>{PROJECT}</Name>
  <CreatedTimestamp>0001-01-01T00:00:00Z</CreatedTimestamp>
  <LastSchemaUpdate>0001-01-01T00:00:00Z</LastSchemaUpdate>
  <LastProcessed>0001-01-01T00:00:00Z</LastProcessed>
  <State>Unprocessed</State>
  <LastUpdate>0001-01-01T00:00:00Z</LastUpdate>
  <DataSourceImpersonationInfo>
    <ImpersonationMode>Default</ImpersonationMode>
    <ImpersonationInfoSecurity>Unchanged</ImpersonationInfoSecurity>
  </DataSourceImpersonationInfo>
</Database>
'''


def main():
    packages = all_packages()
    for p in packages:
        write(os.path.join(ROOT, f"{p.name}.dtsx"), package_xml(p))
    for name, db in CONNECTIONS.items():
        write(os.path.join(ROOT, f"{name}.conmgr"), conmgr_xml(name, db))
    write(os.path.join(ROOT, "Project.params"), project_params_xml())
    write(os.path.join(ROOT, f"{PROJECT}.dtproj"), dtproj_xml(packages))
    write(os.path.join(ROOT, f"{PROJECT}.database"), DATABASE_XML)
    print(f"{len(packages)} packages générés dans {os.path.normpath(ROOT)}")


if __name__ == "__main__":
    main()
