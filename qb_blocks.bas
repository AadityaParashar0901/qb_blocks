$Console
$Resize:On
'$Dynamic

_Console On

'================ Log File ================
Open "log.txt" For Output As #100

If _DirExists("saves") = 0 Then MkDir "saves"

'================ Font ================

$Embed:'./assets/font/PixelCode.ttf','FontA'
$Embed:'./assets/font/JetBrainsMono-Regular.ttf','FontB'
Dim Shared As Long LargeFont, Font, SmallFont
LargeFont = _LoadFont(_Embedded$("FontA"), 48, "MONOSPACE|MEMORY")
Font = _LoadFont(_Embedded$("FontA"), 16, "MONOSPACE|MEMORY")
SmallFont = _LoadFont(_Embedded$("FontB"), 12, "MONOSPACE|MEMORY")

'================ Libraries ================

Const BufferSize = 1024

'$Include:'lib/LongBuffer.bi'

'================ Vector ================

'$Include:'bi/Vectors.bi'

'================ Game Settings ================

Type GameSettings
    As _Unsigned _Byte Fov, Fog, Clouds
    As _Unsigned _Byte MaxJobs
    As _Unsigned Long Fps, RenderDistance
    As Single MouseSensitivity
End Type
Dim Shared As GameSettings GameSettings

Const GameVersion = 6.3
Const MaxRenderDistance = 17
Const MaxJobs = 4
GameSettings.Fov = 90
GameSettings.Fog = 0
GameSettings.Clouds = 1
GameSettings.Fps = 60
GameSettings.RenderDistance = MaxRenderDistance - 1
GameSettings.MouseSensitivity = 0.1

If _FileExists("saves/gamesettings.dat") Then ReadSettings
GameSettings.RenderDistance = _Clamp(0, GameSettings.RenderDistance, MaxRenderDistance - 1)

'================ World Generation ================

Const WaterLevel = 64
Const WorldNoiseSmoothness = 256
Const CloudsHeight = 192

'======== Calculations ========
Const MaxChunks = (2 * MaxRenderDistance - 1) ^ 2
FileLog "Max Chunks: " + _ToStr$(MaxChunks)
Const ChunkDataSize = 65536

'======== Splines ========
Type Spline
    As _Unsigned _Byte Y(0 to 255)
    As Long Image
End Type
Dim Shared As Spline ContinentalSpline, TerrainSpline, DetailSpline
CreateSpline ContinentalSpline, _ReadFile$("assets/splines/continental.txt")
CreateSpline TerrainSpline, _ReadFile$("assets/splines/terrain.txt")
CreateSpline DetailSpline, _ReadFile$("assets/splines/detail.txt")

'================ App State ================

Type AppState
    As _Unsigned _Byte CurrentState, Command
    As _Unsigned Long Progress_Current, Progress_Total
End Type
Const AppState_Starting = 0
Const AppState_Loading_Assets = 1
Const AppState_Page_Menu = 3
Const AppState_Page_Settings = 4
Const AppState_Game_Loading = 5
Const AppState_Game_Play = 6
Const AppState_Game_Pause = 7
Const AppState_Game_Stop = 8
Const AppState_Quit = 255

Const Command_Generating_Textures = 1
Const Command_ChunkQueue = 2
Const Command_ClearAllChunks = 3
Const Command_Continue = 4
Const Command_Quit = 5

Dim Shared As AppState AppState
Dim Shared As Long KeyHit

'================ Graphics ================

Dim Shared CubeVertices(0 To 23) As Vec3_Byte
Dim Shared CubeTextureCoords(0 To 23) As Vec2_Float
Restore CubeModel
For I = 0 To 23
    Read CubeVertices(I).X, CubeVertices(I).Y, CubeVertices(I).Z
    Read CubeTextureCoords(I).X, CubeTextureCoords(I).Y
Next I
CubeModel: '$Include:'assets/models/cube.txt'

Dim Shared As Single Vec4(0 To 3) ' for glVec4

'================ Chunk ================

Const ChunkPipelineSize = ChunkDataSize - 1
Type Chunk
    As Long X, Z
    As _Unsigned _Byte State, AddedToQueue, LevelOfDetail
    As Long TX, TZ
    As _Unsigned _Byte Time(1 To 5)
    As Integer MinimumHeight, MaximumHeight
    As Single Height(0 To 15, 0 To 15)
    As _Unsigned _Byte Temperature(0 To 15, 0 To 15), Humidity(0 To 15, 0 To 15)
    As _Unsigned _Byte Features(0 To 15, 0 to 15)
    As _Unsigned _Byte Blocks(0 To 15, 0 To 255, 0 To 15)
    As _Unsigned _Byte Layers(0 To 255)
End Type
Type PendingChunk
    As _Unsigned _Byte Blocks(0 To 15, 0 To 255, 0 To 15)
End Type

Dim Shared As Vec3_Int glVertices(0 To ChunkPipelineSize, 1 To MaxChunks)
Dim Shared As Vec2_Float glTextureCoords(0 To ChunkPipelineSize, 1 To MaxChunks)
Dim Shared As Vec3_Byte glColors(0 To ChunkPipelineSize, 1 To MaxChunks)
Type glChunkOffset
    As _Offset Vertices, TextureCoords, Colors
    As _Unsigned Long Count
End Type
Type glVerticesCount
    As glChunkOffset Opaque, Transparent
End Type
Dim Shared As glVerticesCount glVerticesCount(1 To MaxChunks)

Dim Shared As Chunk Chunks(0, 0)
Dim Shared As PendingChunk PendingChunks(0, 0)
Dim Shared As Vec3_Long ChunksStart, ChunksEnd
Dim Shared As _Unsigned Long Worker_Jobs_CX(1 To MaxJobs), Worker_Jobs_CZ(1 To MaxJobs)
Dim Shared As _Unsigned Long Worker_Jobs
Dim Shared As LongBuffer ChunkQueue_X, ChunkQueue_Z

Const ChunkState_Empty = 0
Const ChunkState_HeightMap = 1
Const ChunkState_Features = 2
Const ChunkState_Blocks = 3
Const ChunkState_Ready = 4
Const ChunkState_Buffer = 5

Const ChunkGraphSize = ChunkState_Buffer * 256
Dim Shared As String * ChunkGraphSize ChunkGraph

Type TurtleState
    As Single X, Y, Z
    As Single Yaw
    As Single Pitch
End Type
Dim Shared Stack(0 To 255) As TurtleState

'================ Game ================
Type GameState
    As Vec3_Byte SkyColor
    As Vec3_Float glSkyColor
    As Vec3_Long oldPlayerChunk, PlayerChunk
    As Vec3_Byte PlayerInChunk
End Type
Dim Shared As GameState GameState
Dim Shared As Vec3_Int SkyBoxVertices(0 To 23)
Dim Shared As Vec4_Byte SkyBoxColors(0 To 23)
For I = 0 To 23
    SkyBoxVertices(I).X = (CubeVertices(I).X - 0.5) * 2 * (2 * MaxRenderDistance - 1): SkyBoxVertices(I).Y = CubeVertices(I).Y * 256: SkyBoxVertices(I).Z = (CubeVertices(I).Z - 0.5) * 2 * (2 * MaxRenderDistance - 1)
    SkyBoxColors(I).X = 0: SkyBoxColors(I).Y = 0.5: SkyBoxColors(I).Z = 1: SkyBoxColors(I).W = 1
Next I

'======== Clouds ========
Dim Shared As Vec3_Long Cloud_Vertices(0 To 262143)
Dim Shared As Vec4_Byte Cloud_Colors(0 To 262143)
Dim Shared As _Unsigned Long Cloud_TotalQuads
Build_Clouds

'================ Screen ================
Dim Shared As Long MainScreen, ScreenWidth, ScreenHeight
ScreenWidth = 960: ScreenHeight = 540
MainScreen = _NewImage(ScreenWidth, ScreenHeight, 32)
Screen MainScreen
_Font Font
While _ScreenExists = 0: Wend
While _Resize: Wend

_GLRender _Behind

Color _RGB32(255), _RGB32(0, 127)

'================ Assets ================

AppState.CurrentState = AppState_Loading_Assets
'$Include:'bi/AssetsParser.bi'
'_SaveImage "TextureAtlas.png", TextureAtlas

'======== Generate Texture Atlas ========
AppState.Command = Command_Generating_Textures
While AppState.Command: Wend

'================ Player & Camera ================
Type Entity
    As Vec3_Float Position
    Velocity As Vec3_Float: Speed As Single
    As Vec2_Float Angle
    As Single Health, MaxHealth
End Type

Dim Shared As Entity Player
Player.Speed = 4
Player.MaxHealth = 10
Player.Health = Player.MaxHealth
Player.Position.Y = 256

Type Camera
    As Vec3_Float Position, FinalPosition
End Type
Dim Shared As Camera Camera

'================ Game Tick ================

Dim Shared As String * 1024 GameTickGraph

'================ Noise ================

Dim Shared As Integer Perm(0 To 511)

'================ Fps ================
Dim Shared As _Unsigned Integer LFPS, LFPSCount, GFPS, GFPSCount
LFPS = 60: GFPS = 60
Dim As Long FPSCounterTimer
FPSCounterTimer = _FreeTimer
On Timer(FPSCounterTimer, 1) GoSub FpsCounter

'================ Main Loop ================

AppState.CurrentState = AppState_Page_Menu
RefreshChunks

Do
    _Limit 60

    If _Resize Then
        tmpScreenWidth = _ResizeWidth
        tmpScreenHeight = _ResizeHeight
        If tmpScreenWidth > 0 And tmpScreenHeight > 0 Then
            ScreenWidth = tmpScreenWidth
            ScreenHeight = tmpScreenHeight
            tmpScreen& = MainScreen
            MainScreen = _NewImage(ScreenWidth, ScreenHeight, 32)
            Screen MainScreen
            _FreeImage tmpScreen&
            _GLRender _Behind
            Color _RGB32(255), _RGB32(0, 127)
            _Font Font
        End If
    End If

    Select Case AppState.CurrentState
        Case AppState_Page_Menu
            Randomize Timer
            Seed = _RGBA32(Rnd * 256, Rnd * 256, Rnd * 256, Rnd * 256)
            WriteLog "Seed: " + Hex$(Seed)
            InitPerlin Seed
            Build_ChunkQueue 0
            ' Read World
            Timer(FPSCounterTimer) On
            Cls
            AppState.CurrentState = AppState_Game_Loading
            While AppState.Command <> Command_Continue: Wend
            AppState.CurrentState = AppState_Game_Play

        Case AppState_Page_Settings

        Case AppState_Game_Loading

        Case AppState_Game_Play, AppState_Game_Pause

            Build_ChunkQueue 0
            Dim As Vec3_Long tmpChunksStart, tmpChunksEnd
            tmpChunksStart.X = GameState.PlayerChunk.X - GameSettings.RenderDistance
            tmpChunksStart.Z = GameState.PlayerChunk.Z - GameSettings.RenderDistance
            tmpChunksEnd.X = GameState.PlayerChunk.X + GameSettings.RenderDistance
            tmpChunksEnd.Z = GameState.PlayerChunk.Z + GameSettings.RenderDistance
            '======== Load Chunks ========
            For I = 0 To 15
                If ChunkQueue_X.Size > 0 _AndAlso Worker_Jobs < MaxJobs Then Else Exit For
                CX = LongBuffer_Pop(ChunkQueue_X)
                CZ = LongBuffer_Pop(ChunkQueue_Z)
                If InRange(ChunksStart.X, CX, ChunksEnd.X) _AndAlso InRange(ChunksStart.Z, CZ, ChunksEnd.Z) Then Else _Continue
                Chunks(CX, CZ).AddedToQueue = 0
                If Chunks(CX, CZ).State < ChunkState_Buffer _AndAlso InRange(tmpChunksStart.X, CX, tmpChunksEnd.X) _AndAlso InRange(tmpChunksStart.Z, CZ, tmpChunksEnd.Z) Then
                    Worker_Jobs = Worker_Jobs + 1
                    Worker_Jobs_CX(Worker_Jobs) = CX
                    Worker_Jobs_CZ(Worker_Jobs) = CZ
                    AddChunkToQueue CX + 1, CZ
                    AddChunkToQueue CX - 1, CZ
                    AddChunkToQueue CX, CZ + 1
                    AddChunkToQueue CX, CZ - 1
                    AddChunkToQueue CX, CZ
                Else
                    AddChunkToQueue CX, CZ
                End If
            Next I
            Tick

        Case AppState_Game_Stop

        Case AppState_Quit

    End Select

    Work

    Select Case AppState.Command
        Case Command_ChunkQueue
            Build_ChunkQueue Command_ChunkQueue
            RefreshChunks
            AppState.Command = 0

        Case Command_ClearAllChunks
            ClearAllChunks
            AppState.Command = 0

        Case Command_Quit
            WriteSettings
            Exit Do

    End Select

    LFPSCount = LFPSCount + 1
Loop
System

'======== Fps Counter ========
FpsCounter:
If LFPSCount Then LFPS = LFPSCount
LFPSCount = 0
If GFPSCount Then GFPS = GFPSCount
GFPSCount = 0
Return

'================ Physics ================
Sub SimulateEntity (Entity As Entity, Speed!)
    Entity.Position.X = Entity.Position.X + Entity.Velocity.X * Speed!
    Entity.Position.Y = Entity.Position.Y + Entity.Velocity.Y * Speed!
    Entity.Position.Z = Entity.Position.Z + Entity.Velocity.Z * Speed!
    Entity.Velocity.X = _IIf(Abs(Entity.Velocity.X) > 0.1, Entity.Velocity.X * 0.9, 0)
    Entity.Velocity.Y = _IIf(Abs(Entity.Velocity.Y) > 0.1, Entity.Velocity.Y * 0.9, 0)
    Entity.Velocity.Z = _IIf(Abs(Entity.Velocity.Z) > 0.1, Entity.Velocity.Z * 0.9, 0)
End Sub
Sub MoveEntity (Entity As Entity, Angle!, Speed!)
    Entity.Velocity.X = Entity.Velocity.X + Cos(_D2R(Angle!)) * Speed!
    Entity.Velocity.Z = Entity.Velocity.Z + Sin(_D2R(Angle!)) * Speed!
End Sub

'================ Game ================
Sub Tick Static
    Static As Single lastTime, dTime
    dTime = Timer(0.01) - lastTime
    If dTime < 0.1 Then Exit Sub
    lastTime = Timer(0.01)
    GameTickGraph = Mid$(GameTickGraph, 5) + MKI$(1000 * dTime)

    If AppState.CurrentState <> AppState_Game_Play Then Exit Sub
    GameState.SkyColor.X = 0: GameState.SkyColor.Y = 127: GameState.SkyColor.Z = 255
    GameState.glSkyColor.X = 0: GameState.glSkyColor.Y = 0.5: GameState.glSkyColor.Z = 1
End Sub

'================ GL ================

Sub _GL Static
    Static As Long TextureAtlasHandle
    Static As _Unsigned _Byte DebugMenu, NewFov, Zoom, Command_Freeze
    Static As LongBuffer TransparentChunks
    Static As _Unsigned Long ChunksLoaded, QuadsLoaded

    KeyHit = _KeyHit
    Select Case AppState.CurrentState
        Case AppState_Game_Play
            Cls , 0

            Camera.Position = Player.Position
            ' W
            If _KeyDown(87) Or _KeyDown(119) Then MoveEntity Player, Player.Angle.X - 90, Player.Speed
            ' S
            If _KeyDown(83) Or _KeyDown(115) Then MoveEntity Player, Player.Angle.X + 90, Player.Speed
            ' A
            If _KeyDown(65) Or _KeyDown(97) Then MoveEntity Player, Player.Angle.X - 180, Player.Speed
            ' D
            If _KeyDown(68) Or _KeyDown(100) Then MoveEntity Player, Player.Angle.X, Player.Speed
            ' C
            Zoom = (_KeyDown(67) Or _KeyDown(99)) And 1
            ' Space
            Player.Velocity.Y = _IIf(_KeyDown(32), 4 * Player.Speed, Player.Velocity.Y)
            ' Left Shift
            Player.Velocity.Y = _IIf(_KeyDown(100304), -4 * Player.Speed, Player.Velocity.Y)
            ' Left Ctrl
            Player.Speed = _IIf(_KeyDown(100306), 16, 1)

            SimulateEntity Player, 1 / GFPS

            Select Case KeyHit
                Case 27: AppState.CurrentState = AppState_Game_Pause
                Case 15616: DebugMenu = Not DebugMenu
                Case 82, 114: AppState.Command = Command_ClearAllChunks
                Case 92: Command_Freeze = Not Command_Freeze
            End Select

            GameState.oldPlayerChunk = GameState.PlayerChunk
            GameState.PlayerChunk.X = Int(Player.Position.X / 16)
            GameState.PlayerChunk.Y = Int(Player.Position.Y / 16)
            GameState.PlayerChunk.Z = Int(Player.Position.Z / 16)
            GameState.PlayerInChunk.X = Int(Player.Position.X) And 15
            GameState.PlayerInChunk.Y = Int(Player.Position.Y) And 255
            GameState.PlayerInChunk.Z = Int(Player.Position.Z) And 15
            If GameState.oldPlayerChunk.X <> GameState.PlayerChunk.X Or GameState.oldPlayerChunk.Z <> GameState.PlayerChunk.Z Then AppState.Command = _IIf(Command_Freeze, 0, Command_ChunkQueue)

            _MouseHide
            While _MouseInput
                dMouseX = _MouseX - ScreenWidth / 2
                dMouseY = _MouseY - ScreenHeight / 2
                Player.Angle.X = ClampCycle(0, Player.Angle.X + dMouseX * GameSettings.MouseSensitivity, 360)
                Player.Angle.Y = _Clamp(-90, Player.Angle.Y + dMouseY * GameSettings.MouseSensitivity, 90)
            Wend
            _MouseMove _Width / 2, _Height / 2
            _FPS GameSettings.Fps

        Case AppState_Game_Pause
            Cls , 0

            _MouseShow
            While _MouseInput: Wend
            _PrintString ((ScreenWidth - _PrintWidth("Paused")) / 2, _FontHeight * 1.5), "Paused"
            Select Case KeyHit
                Case 27: AppState.CurrentState = AppState_Game_Play
            End Select
            _FPS _Max(4, _ShR(GameSettings.Fps, 2))

    End Select
    Select Case AppState.CurrentState
        Case AppState_Starting

        Case AppState_Loading_Assets
            gl_DrawLoadingMenuText "Loading Assets"

        Case AppState_Page_Menu
        Case AppState_Page_Settings
        Case AppState_Game_Loading
            ' Load saved chunks here
            AppState.Command = Command_Continue

        Case AppState_Game_Play, AppState_Game_Pause
            _glViewport 0, 0, ScreenWidth - 1, ScreenHeight - 1
            _glEnable _GL_BLEND
            _glEnable _GL_DEPTH_TEST
            _glClearColor GameState.glSkyColor.X, GameState.glSkyColor.Y, GameState.glSkyColor.Z, 1
            _glClear _GL_COLOR_BUFFER_BIT Or _GL_DEPTH_BUFFER_BIT
            _glRotatef Player.Angle.Y, 1, 0, 0
            _glRotatef Player.Angle.X, 0, 1, 0
            _glPushMatrix
            _glTranslatef -Camera.Position.X, -Camera.Position.Y, -Camera.Position.Z
            _glMatrixMode _GL_PROJECTION
            _glLoadIdentity
            NewFov = NewFov + (GameSettings.Fov - Zoom * (GameSettings.Fov - 30) - NewFov) / 4
            _gluPerspective NewFov, ScreenWidth / ScreenHeight, 0.1, 384
            _glMatrixMode _GL_MODELVIEW

            _glEnable _GL_CULL_FACE
            _glCullFace _GL_BACK

            _glEnable _GL_TEXTURE_2D
            _glBindTexture _GL_TEXTURE_2D, TextureAtlasHandle
            _glEnableClientState _GL_VERTEX_ARRAY
            _glEnableClientState _GL_TEXTURE_COORD_ARRAY
            _glEnableClientState _GL_COLOR_ARRAY

            tmpChunks = 0: tmpQuads = 0
            LongBuffer_Clear TransparentChunks
            For ChunkId = 1 To MaxChunks
                _glVertexPointer 3, _GL_SHORT, 0, glVerticesCount(ChunkId).Opaque.Vertices
                _glTexCoordPointer 2, _GL_FLOAT, 0, glVerticesCount(ChunkId).Opaque.TextureCoords
                _glColorPointer 3, _GL_UNSIGNED_BYTE, 0, glVerticesCount(ChunkId).Opaque.Colors
                _glDrawArrays _GL_QUADS, 0, glVerticesCount(ChunkId).Opaque.Count
                tmpChunks = tmpChunks + Sgn(glVerticesCount(ChunkId).Opaque.Count + glVerticesCount(ChunkId).Transparent.Count)
                tmpQuads = tmpQuads + glVerticesCount(ChunkId).Opaque.Count
                If glVerticesCount(ChunkId).Transparent.Count = 0 Then _Continue
                LongBuffer_Push TransparentChunks, ChunkId
            Next ChunkId

            _glDisable _GL_CULL_FACE
            _glEnable _GL_ALPHA_TEST
            _glAlphaFunc _GL_GREATER, 0.1
            While TransparentChunks.Size
                ChunkId = LongBuffer_Pop(TransparentChunks)
                _glVertexPointer 3, _GL_SHORT, 0, glVerticesCount(ChunkId).Transparent.Vertices
                _glTexCoordPointer 2, _GL_FLOAT, 0, glVerticesCount(ChunkId).Transparent.TextureCoords
                _glColorPointer 3, _GL_UNSIGNED_BYTE, 0, glVerticesCount(ChunkId).Transparent.Colors
                _glDrawArrays _GL_QUADS, 0, glVerticesCount(ChunkId).Transparent.Count
                tmpQuads = tmpQuads + glVerticesCount(ChunkId).Transparent.Count
            Wend
            ChunksLoaded = tmpChunks
            QuadsLoaded = tmpQuads
            _glDisableClientState _GL_COLOR_ARRAY
            _glDisableClientState _GL_TEXTURE_COORD_ARRAY
            _glDisableClientState _GL_VERTEX_ARRAY

            _glDisable _GL_ALPHA_TEST
            _glDisable _GL_TEXTURE_2D

            _glEnable _GL_CULL_FACE
            DrawClouds
            DrawSkyBox
            _glDisable _GL_CULL_FACE

            _glPopMatrix

            _glDisable _GL_DEPTH_TEST
            _glDisable _GL_BLEND
            _glFlush

            _PrintString (0, 0), "Fps: " + _ToStr$(LFPS) + "/" + _ToStr$(GFPS)
            _PrintString (0, 16), "Position: " + _ToStr$(Player.Position.X) + Str$(Player.Position.Y) + Str$(Player.Position.Z) + ", Angle: " + _ToStr$(Player.Angle.X) + Str$(Player.Angle.Y)

            If DebugMenu Then
                _PrintString (0, 32), "Chunks: (" + _ToStr$(ChunksStart.X) + " ~ " + _ToStr$(ChunksEnd.X) + ", " + _ToStr$(ChunksStart.Z) + " ~ " + _ToStr$(ChunksEnd.Z) + "), Loaded=" + _ToStr$(ChunksLoaded) + ", Queue=" + _ToStr$(ChunkQueue_X.Size)
                _PrintString (0, 48), "Quads: " + _ToStr$(QuadsLoaded)
                PrintDebug 0, 64, "Continentalness=" + _ToStr$(GetContinentalNoise(Player.Position.X, Player.Position.Z))
                PrintDebug 0, 76, "Terrain=" + _ToStr$(GetTerrainNoise(Player.Position.X, Player.Position.Z))
                PrintDebug 0, 88, "Detail=" + _ToStr$(GetDetailNoise(Player.Position.X, Player.Position.Z))
                PrintDebug 0, 100, "Temperature=" + _ToStr$(GetTemperatureNoise(Player.Position.X, Player.Position.Z))
                PrintDebug 0, 112, "Humidity=" + _ToStr$(GetHumidityNoise(Player.Position.X, Player.Position.Z))

                For I = 1 To 256 ' Chunk Graph
                    T$ = Mid$(ChunkGraph, (I - 1) * ChunkState_Buffer + 1, ChunkState_Buffer)
                    K = _Height - 5
                    For J = 1 To ChunkState_Buffer
                        Line (I + 8, K)-(I + 8, K - Asc(T$, J)), _RGB32(_IIf(J And 4, 255, 0), _IIf(J And 2, 255, 0), 255 And _IIf(J And 1, 255, 0))
                        K = K - Asc(T$, J)
                    Next J
                Next I
            End If

            _Display

        Case AppState_Game_Stop
        Case AppState_Quit
            gl_DrawLoadingMenuText "Exiting"
            _glDeleteTextures 1, _Offset(TextureAtlasHandle)
            AppState.Command = Command_Quit

    End Select
    Select Case AppState.Command
        Case Command_Generating_Textures
            WriteLog "Generating Textures"
            gl_generateTexture TextureAtlasHandle, TextureAtlas
            AppState.Command = 0
    End Select

    If _Exit Then
        AppState.CurrentState = AppState_Quit
        AppState.Command = Command_Quit
    End If

    GFPSCount = GFPSCount + 1
End Sub

'================ Chunk ================

'$Include:'bi/Chunk.bm'
Sub AddChunkToQueue (CX As Long, CZ As Long)
    If (InRange(ChunksStart.X, CX, ChunksEnd.X) And InRange(ChunksStart.Z, CZ, ChunksEnd.Z)) = 0 _OrElse Chunks(CX, CZ).AddedToQueue Then Exit Sub
    LongBuffer_Push ChunkQueue_X, CX
    LongBuffer_Push ChunkQueue_Z, CZ
    Chunks(CX, CZ).AddedToQueue = -1
End Sub

Sub Work Static
    Static As Long CX, CZ, TX, TZ
    Static As Chunk Chunk
    Dim As _Unsigned _Byte tmpBlocks(0 To 5)
    Static As _Unsigned _Byte TemperatureColor, HumidityColor
    Static As _Unsigned Long FinalColor
    Static As LongBuffer OpaqueQueue, TransparentQueue
    For iJob = 1 To Worker_Jobs
        CX = Worker_Jobs_CX(iJob)
        CZ = Worker_Jobs_CZ(iJob)
        PX = CX * 16: PZ = CZ * 16
        startTime = Timer(0.01)

        Chunk = Chunks(CX, CZ)
        Select Case Chunk.State
            Case ChunkState_Empty
                Chunk.TX = PX: Chunk.TZ = PZ

                Chunk.LevelOfDetail = 0

                Chunk.MinimumHeight = 255
                Chunk.MaximumHeight = WaterLevel

                lodStep = _ShL(1, Chunk.LevelOfDetail)
                For X = 0 To 15 Step lodStep: For Z = 0 To 15 Step lodStep
                        TX = PX + X: TZ = PZ + Z
                        Chunk.Height(X, Z) = _Clamp(0, (ApplySpline(ContinentalSpline, GetContinentalNoise(TX, TZ)) + 3 * ApplySpline(TerrainSpline, GetTerrainNoise(TX, TZ)) + 2 * ApplySpline(DetailSpline, GetDetailNoise(TX, TZ)) - GetErosionNoise(TX, TZ)) / 8, 255)
                        Chunk.Temperature(X, Z) = _Clamp(0, GetTemperatureNoise(TX, TZ) * 256, 255)
                        Chunk.Humidity(X, Z) = _Clamp(0, GetHumidityNoise(TX, TZ) * 256, 255)
                        Chunk.Features(X, Z) = _IIf(Chunk.Height(X, Z) > WaterLevel, GetFeatureNoise(TX, TZ), 0)
                        Chunk.Blocks(X, 0, Z) = getBlockID("bedrock")
                        Chunk.Layers(0) = 1
                Next Z, X
                Chunk.State = ChunkState_HeightMap

            Case ChunkState_HeightMap
                lodStep = _ShL(1, Chunk.LevelOfDetail)
                ChunkId = getChunkId(CX, CZ)
                glVerticesCount(ChunkId).Opaque.Count = 0
                glVerticesCount(ChunkId).Transparent.Count = 0
                For X = 0 To 15 Step lodStep: For Z = 0 To 15 Step lodStep
                        Height = Chunk.Height(X, Z)
                        dHeight = Height - WaterLevel
                        Height = Int(Height)
                        CaveHeight = 255
                        Biome = _IIf(Chunk.Temperature(X, Z) > 191, 3, _IIf(Chunk.Temperature(X, Z) > 63, 2, 1))
                        For Y = 1 To Height - 2
                            Chunk.Blocks(X, Y, Z) = getBlockID("stone")
                            Chunk.Layers(Y) = Chunk.Layers(Y) Or 1
                        Next Y
                        For Y = _Clamp(0, Height - 2, 255) To Height
                            Chunk.Blocks(X, Y, Z) = _IIf(Y = Height, _IIf(Biome = 3, getBlockID("snow"), _IIf(Biome = 2, getBlockID("grass"), getBlockID("sand"))), getBlockID("dirt"))
                            Chunk.Layers(Y) = Chunk.Layers(Y) Or 1
                        Next Y
                        For Y = Height To WaterLevel
                            Block = _IIf(dHeight < 0.5, getBlockID("water"), _IIf(Biome = 3, getBlockID("snow"), _IIf(Biome = 2, getBlockID("grass"), getBlockID("sand"))))
                            Chunk.Blocks(X, Y, Z) = Block
                            Chunk.Layers(Y) = Chunk.Layers(Y) Or _IIf(isTransparent(Block), 2, 1)
                        Next Y
                        For Y = _Max(Height, WaterLevel) + 1 To 255
                            Chunk.Blocks(X, Y, Z) = 0
                            Chunk.Layers(Y) = Chunk.Layers(Y) Or 4
                        Next Y

                        Chunk.MinimumHeight = _Clamp(0, Chunk.MinimumHeight, _Min(CaveHeight, Height) - 2)
                        Chunk.MaximumHeight = _Clamp(Height + 1, Chunk.MaximumHeight, 255)
                Next Z, X
                Chunk.State = ChunkState_Features

            Case ChunkState_Features
                For X = 0 To 15: For Z = 0 To 15
                        Y = Int(Chunk.Height(X, Z)) + 1
                        Biome = _IIf(Chunk.Temperature(X, Z) > 191, 3, _IIf(Chunk.Temperature(X, Z) > 63, 2, 1))
                        Select Case Chunk.Features(X, Z)
                            Case 0:
                            Case 1: GenerateLTree PX + X, Y, PZ + Z, Biome
                            Case 2: Chunk.Blocks(X, Y, Z) = getBlockID("pink_tulip")
                            Case 3: Chunk.Blocks(X, Y, Z) = getBlockID("white_tulip")
                            Case 4: Chunk.Blocks(X, Y, Z) = getBlockID("allium")
                        End Select
                Next Z, X
                Chunk.State = ChunkState_Blocks

            Case ChunkState_Blocks
                For X = 0 To 15: For Z = 0 To 15: For Y = 0 To 255
                            P = PendingChunks(CX, CZ).Blocks(X, Y, Z)
                            If P > TotalBlocks Then
                                WriteLog "Error: Invalid Pending Block " + _ToStr$(P)
                                _Continue
                            End If
                            Chunk.Blocks(X, Y, Z) = _IIf(P, P, Chunk.Blocks(X, Y, Z))
                            Chunk.Layers(Y) = Chunk.Layers(Y) Or _IIf(P, _IIf(isTransparent(P), 2, 1), 0)
                            Chunk.MinimumHeight = _Min(Chunk.MinimumHeight, _IIf(P, Y, 255))
                            Chunk.MaximumHeight = _Max(Chunk.MaximumHeight, _IIf(P, Y, 0))
                Next Y, Z, X
                Chunk.State = ChunkState_Ready

            Case ChunkState_Ready
                LongBuffer_Clear OpaqueQueue
                LongBuffer_Clear TransparentQueue

                lodStep = _ShL(1, Chunk.LevelOfDetail)
                X0 = lodStep - 1: X1 = 16 - lodStep
                Y0 = 1: Y1 = 254
                Z0 = lodStep - 1: Z1 = 16 - lodStep

                ChunkId = getChunkId(CX, CZ)
                For Y = Chunk.MinimumHeight To Chunk.MaximumHeight
                    LayerCombination = Chunk.Layers(Y) Or _IIf(Y > 0, Chunk.Layers(Y - 1), 0) Or _IIf(Y < 255, Chunk.Layers(Y + 1), 0)
                    If LayerCombination < 3 Or LayerCombination = 4 Then _Continue

                    For X = 0 To 15 Step lodStep: For Z = 0 To 15 Step lodStep
                            Block = Chunk.Blocks(X, Y, Z)
                            BlockIsInsideChunk = (X0 < X And X < X1) _AndAlso (Y0 < Y And Y < Y1) _AndAlso (Z0 < Z And Z < Z1)
                            If Block = 0 Then
                                _Continue
                            ElseIf Block > TotalBlocks Then
                                WriteLog "Error: Invalid Block " + _ToStr$(Block)
                                _Continue
                            End If

                            tmpBlocks(0) = _IIf(BlockIsInsideChunk, Chunk.Blocks(X + lodStep, Y, Z), getBlock(PX + X + lodStep, Y, PZ + Z))
                            tmpBlocks(1) = _IIf(BlockIsInsideChunk, Chunk.Blocks(X - lodStep, Y, Z), getBlock(PX + X - lodStep, Y, PZ + Z))
                            tmpBlocks(2) = _IIf(BlockIsInsideChunk, Chunk.Blocks(X, Y + 1, Z), getBlock(PX + X, Y + 1, PZ + Z))
                            tmpBlocks(3) = _IIf(BlockIsInsideChunk, Chunk.Blocks(X, Y - 1, Z), getBlock(PX + X, Y - 1, PZ + Z))
                            tmpBlocks(4) = _IIf(BlockIsInsideChunk, Chunk.Blocks(X, Y, Z + lodStep), getBlock(PX + X, Y, PZ + Z + lodStep))
                            tmpBlocks(5) = _IIf(BlockIsInsideChunk, Chunk.Blocks(X, Y, Z - lodStep), getBlock(PX + X, Y, PZ + Z - lodStep))

                            omitBlockFace = omitBlockFace(Block)

                            Visibility = isTransparent(tmpBlocks(0)) And Not (_ReadBit(omitBlockFace, 0) And Block = tmpBlocks(0)) And (Blocks(Block).Faces(0) <> 0)
                            Visibility = Visibility Or _ShL(isTransparent(tmpBlocks(1)) And Not (_ReadBit(omitBlockFace, 1) And Block = tmpBlocks(1)) And (Blocks(Block).Faces(1) <> 0), 1)
                            Visibility = Visibility Or _ShL(isTransparent(tmpBlocks(2)) And Not (_ReadBit(omitBlockFace, 2) And Block = tmpBlocks(2)) And (Blocks(Block).Faces(2) <> 0), 2)
                            Visibility = Visibility Or _ShL(isTransparent(tmpBlocks(3)) And Not (_ReadBit(omitBlockFace, 3) And Block = tmpBlocks(3)) And (Blocks(Block).Faces(3) <> 0), 3)
                            Visibility = Visibility Or _ShL(isTransparent(tmpBlocks(4)) And Not (_ReadBit(omitBlockFace, 4) And Block = tmpBlocks(4)) And (Blocks(Block).Faces(4) <> 0), 4)
                            Visibility = Visibility Or _ShL(isTransparent(tmpBlocks(5)) And Not (_ReadBit(omitBlockFace, 5) And Block = tmpBlocks(5)) And (Blocks(Block).Faces(5) <> 0), 5)
                            If Visibility = 0 Then _Continue

                            If isTransparent(Block) Then
                                LongBuffer_Push TransparentQueue, _ShL(Visibility, 16) Or _ShL(X, 12) Or _ShL(Y, 4) Or Z
                            Else
                                LongBuffer_Push OpaqueQueue, _ShL(Visibility, 16) Or _ShL(X, 12) Or _ShL(Y, 4) Or Z
                            End If
                Next Z, X, Y

                VertexId = 0
                glVerticesCount(ChunkId).Opaque.Vertices = _Offset(glVertices(0, ChunkId)): glVerticesCount(ChunkId).Opaque.TextureCoords = _Offset(glTextureCoords(0, ChunkId)): glVerticesCount(ChunkId).Opaque.Colors = _Offset(glColors(0, ChunkId))
                While OpaqueQueue.Size
                    XYZ = LongBuffer_Pop(OpaqueQueue)
                    Visibility = _ShR(XYZ, 16) And 63: X = _ShR(XYZ, 12) And 15: Y = _ShR(XYZ, 4) And 255: Z = XYZ And 15
                    Block = Chunk.Blocks(X, Y, Z)
                    If VertexId + 24 >= ChunkPipelineSize Then Exit For
                    TemperatureColor = Chunk.Temperature(X, Z)
                    HumidityColor = Chunk.Humidity(X, Z)
                    FinalColor = _RGB32(191 + _ShR(TemperatureColor * 20, 8), 191 + _ShR(HumidityColor * 10, 8), 191 - _ShR(TemperatureColor * 15, 8))
                    For I = 0 To 23
                        If (I And 3) = 0 Then
                            Face = _ShR(I, 2)
                            If _ReadBit(Visibility, Face) = 0 Then I = I + 3: _Continue
                            TextureId = Blocks(Block).Faces(Face)
                            TextureOffsetX = Textures(TextureId).X
                            TextureOffsetY = Textures(TextureId).Y
                            Light = _IIf(Face >= 4, 11, _IIf(Face = 3, 7, _IIf(Face = 2, 15, 9)))
                        End If
                        glVertices(VertexId, ChunkId).X = PX + X + CubeVertices(I).X * lodStep
                        glVertices(VertexId, ChunkId).Y = Y + CubeVertices(I).Y
                        glVertices(VertexId, ChunkId).Z = PZ + Z + CubeVertices(I).Z * lodStep
                        glTextureCoords(VertexId, ChunkId).X = TextureOffsetX + _IIf(CubeTextureCoords(I).X, CalculatedTextureSize, 0)
                        glTextureCoords(VertexId, ChunkId).Y = TextureOffsetY + _IIf(CubeTextureCoords(I).Y, CalculatedTextureSize, 0)
                        __color = AmbientOcclusion(PX + X, Y, PZ + Z, I, 15 - Light)
                        glColors(VertexId, ChunkId).X = _ShR(__color * _Red32(FinalColor), 8)
                        glColors(VertexId, ChunkId).Y = _ShR(__color * _Green32(FinalColor), 8)
                        glColors(VertexId, ChunkId).Z = _ShR(__color * _Blue32(FinalColor), 8)
                        VertexId = VertexId + 1
                    Next I
                Wend
                glVerticesCount(ChunkId).Opaque.Count = VertexId

                glVerticesCount(ChunkId).Transparent.Vertices = _Offset(glVertices(VertexId, ChunkId)): glVerticesCount(ChunkId).Transparent.TextureCoords = _Offset(glTextureCoords(VertexId, ChunkId)): glVerticesCount(ChunkId).Transparent.Colors = _Offset(glColors(VertexId, ChunkId))
                While TransparentQueue.Size
                    XYZ = LongBuffer_Pop(TransparentQueue)
                    Visibility = _ShR(XYZ, 16) And 63: X = _ShR(XYZ, 12) And 15: Y = _ShR(XYZ, 4) And 255: Z = XYZ And 15
                    Block = Chunk.Blocks(X, Y, Z)
                    If VertexId + 24 >= ChunkPipelineSize Then Exit While
                    ModelId = Blocks(Block).ModelId
                    Select Case ModelId
                        Case 0
                            TemperatureColor = Chunk.Temperature(X, Z)
                            HumidityColor = Chunk.Humidity(X, Z)
                            FinalColor = _RGB32(191 + _ShR(TemperatureColor * 40, 8), 191 + _ShR(HumidityColor * 20, 8), 191 - _ShR(TemperatureColor * 30, 8))
                            For I = 0 To 23
                                If (I And 3) = 0 Then
                                    Face = _ShR(I, 2)
                                    If _ReadBit(Visibility, Face) = 0 Then I = I + 3: _Continue
                                    TextureId = Blocks(Block).Faces(Face)
                                    TextureOffsetX = Textures(TextureId).X
                                    TextureOffsetY = Textures(TextureId).Y
                                    Light = _IIf(Face >= 4, 11, _IIf(Face = 3, 7, _IIf(Face = 2, 15, 9)))
                                End If
                                glVertices(VertexId, ChunkId).X = PX + X + CubeVertices(I).X * lodStep
                                glVertices(VertexId, ChunkId).Y = Y + CubeVertices(I).Y
                                glVertices(VertexId, ChunkId).Z = PZ + Z + CubeVertices(I).Z * lodStep
                                glTextureCoords(VertexId, ChunkId).X = TextureOffsetX + _IIf(CubeTextureCoords(I).X, CalculatedTextureSize, 0)
                                glTextureCoords(VertexId, ChunkId).Y = TextureOffsetY + _IIf(CubeTextureCoords(I).Y, CalculatedTextureSize, 0)
                                __color = AmbientOcclusion(PX + X, Y, PZ + Z, I, 15 - Light)
                                glColors(VertexId, ChunkId).X = _ShR(__color * _Red32(FinalColor), 8)
                                glColors(VertexId, ChunkId).Y = _ShR(__color * _Green32(FinalColor), 8)
                                glColors(VertexId, ChunkId).Z = _ShR(__color * _Blue32(FinalColor), 8)
                                VertexId = VertexId + 1
                            Next I

                        Case Else ' Custom Model
                            TextureId = Blocks(Block).Faces(0)
                            TextureOffsetX = Textures(TextureId).X
                            TextureOffsetY = Textures(TextureId).Y
                            For I = 0 To CustomModels(ModelId).Count - 1
                                glVertices(VertexId, ChunkId).X = PX + X + CustomModels(ModelId).Vertices(I).X * lodStep
                                glVertices(VertexId, ChunkId).Y = Y + CustomModels(ModelId).Vertices(I).Y
                                glVertices(VertexId, ChunkId).Z = PZ + Z + CustomModels(ModelId).Vertices(I).Z * lodStep
                                glTextureCoords(VertexId, ChunkId).X = TextureOffsetX + _IIf(CustomModels(ModelId).TextureCoords(I).X, CalculatedTextureSize, 0)
                                glTextureCoords(VertexId, ChunkId).Y = TextureOffsetY + _IIf(CustomModels(ModelId).TextureCoords(I).Y, CalculatedTextureSize, 0)
                                __color = 15 * Light
                                glColors(VertexId, ChunkId).X = __color
                                glColors(VertexId, ChunkId).Y = __color
                                glColors(VertexId, ChunkId).Z = __color
                                VertexId = VertexId + 1
                            Next I
                    End Select
                Wend
                glVerticesCount(ChunkId).Transparent.Count = VertexId - glVerticesCount(ChunkId).Opaque.Count

                Chunk.State = ChunkState_Buffer
                Chunk.AddedToQueue = 0

        End Select
        NewState = Chunk.State
        Chunk.Time(NewState) = _Clamp(0, 256 * (Timer(0.01) - startTime), 255)
        If Chunk.State = ChunkState_Buffer Then
            T$ = "": For I = 1 To ChunkState_Buffer
                T$ = T$ + Chr$(Chunk.Time(I))
            Next I
            ChunkGraph = Mid$(ChunkGraph, Len(T$) + 1) + T$
        End If
        Chunks(CX, CZ) = Chunk
    Next iJob
    Worker_Jobs = 0
End Sub
Function GetContinentalNoise (X As Long, Z As Long) Static
    GetContinentalNoise = Fractal2(X, Z, 1024, 1, 0) * 0.5 + 0.5
End Function
Function GetTerrainNoise (X As Long, Z As Long) Static
    GetTerrainNoise = Fractal2(X, Z, 256, 3, 1) * 0.5 + 0.5
End Function
Function GetDetailNoise (X As Long, Z As Long) Static
    GetDetailNoise = Fractal2(X, Z, 256, 5, 2) * 0.5 + 0.5
End Function
Function GetErosionNoise (X As Long, Z As Long) Static
    GetErosionNoise = 64 * Abs(Fractal2(X, Z, 256, 3, 3))
End Function
Function GetTemperatureNoise (X As Long, Z As Long) Static
    GetTemperatureNoise = Fractal2(X, Z, 1024, 2, 4) * 0.5 + 0.5
End Function
Function GetHumidityNoise (X As Long, Z As Long) Static
    GetHumidityNoise = Fractal2(X, Z, 1024, 0, 5) * 0.5 + 0.5
End Function
Function GetFeatureNoise (X As Long, Z As Long) Static
    Static As Single N
    If InRange(0.1, Fractal2(X, Z, 4, 2, 6), 0.2) _AndAlso InRange(-0.5, Fractal2(X, Z, 8, 2, 7), -0.4) Then
        GetFeatureNoise = 1 ' Tree
        Exit Function
    End If
    N = Fractal2(X, Z, 16, 2, 8)
    If N > 0.4 And N < 0.5 Then
        N = Fractal2(X, Z, 16, 0, 9)
        GetFeatureNoise = _Clamp(2, N + 3, 4) ' Flower
    Else
        GetFeatureNoise = 0 ' Nothing
    End If
End Function

'$Include:'bi/Tree.bm'

Function AmbientOcclusion~%% (X As Long, Y As Integer, Z As Long, vertexIndex As _Byte, CurrentLight As _Unsigned _Byte) Static
    Static As _Byte dX, dY, dZ
    Static As _Byte side1, side2, corner
    dX = _ShL(CubeVertices(vertexIndex).X, 1) - 1
    dY = _ShL(CubeVertices(vertexIndex).Y, 1) - 1
    dZ = _ShL(CubeVertices(vertexIndex).Z, 1) - 1
    corner = isFullBlock(getBlock(X + dX, Y + dY, Z + dZ))
    side1 = isFullBlock(getBlock(X + dX, Y + dY, Z))
    side2 = isFullBlock(getBlock(X, Y + dY, Z + dZ))
    AmbientOcclusion = 255 - 15 * _Clamp(0, side1 + side2 + corner + CurrentLight, 15)
End Function
Function getChunkId~& (X As Long, Z As Long) Static
    T = MaxRenderDistance * 2 - 1
    getChunkId = 1 + ModFloor(Z * T + X, MaxChunks)
End Function
Function getBlock~%% (X As Long, Y As Long, Z As Long) Static
    Static As Long CX, CZ
    Static As _Unsigned _Byte B, P
    CX = Int(X / 16)
    CZ = Int(Z / 16)
    If InRange(LBound(Chunks, 1), CX, UBound(Chunks, 1)) And InRange(LBound(Chunks, 2), CZ, UBound(Chunks, 2)) Then
        P = PendingChunks(CX, CZ).Blocks(X And 15, Y And 255, Z And 15)
        B = Chunks(CX, CZ).Blocks(X And 15, Y And 255, Z And 15)
        If P > UBound(Blocks) Then WriteLog "Error: Unknown Value of Pending Block (" + _ToStr$(X) + "," + _ToStr$(Y) + "," + _ToStr$(Z) + "): " + _ToStr$(P): P = 0
        If B > UBound(Blocks) Then WriteLog "Error: Unknown Value of Block (" + _ToStr$(X) + "," + _ToStr$(Y) + "," + _ToStr$(Z) + "): " + _ToStr$(B): B = 0
        getBlock = _IIf(P, P, B)
    Else
        WriteLog "Warning: getBlock trying To access unaccessible area: (" + _ToStr$(CX) + ", " + _ToStr$(CZ) + ")"
        getBlock = 0
    End If
End Function
Sub setBlock (X As Long, Y As Long, Z As Long, Block As _Unsigned _Byte) Static
    Static As Long CX, CZ
    CX = Int(X / 16)
    CZ = Int(Z / 16)
    If InRange(LBound(Chunks, 1), CX, UBound(Chunks, 1)) And InRange(LBound(Chunks, 2), CZ, UBound(Chunks, 2)) Then
        PendingChunks(CX, CZ).Blocks(X And 15, Y And 255, Z And 15) = Block
    Else
        WriteLog "Warning: setBlock trying To access unaccessible area: (" + _ToStr$(CX) + ", " + _ToStr$(CZ) + ")"
    End If
End Sub

'======== Splines ========
Sub CreateSpline (S As Spline, L As String) Static
    Static As _Unsigned _Byte X0, Y0, X1, Y1
    Static As Single m, c
    Static As _Unsigned _Byte t
    Static As _Unsigned Long I, X
    L = ListStringFromString(L)
    If S.Image < -1 Then _FreeImage S.Image
    S.Image = _NewImage(256, 256, 32)
    _Dest S.Image
    For I = 1 To ListStringLength(L) - 2 Step 2
        X0 = Val(ListStringGet(L, I))
        Y0 = Val(ListStringGet(L, I + 1))
        X1 = Val(ListStringGet(L, I + 2))
        Y1 = Val(ListStringGet(L, I + 3))
        m = (Y1 - Y0) / (X1 - X0)
        c = Y0 - m * X0
        t = _ShR(I, 2)
        For X = X0 To X1
            S.Y(X) = m * X + c
            Line (X, 255 - S.Y(X))-(X, 255), _RGB32(_IIf(t And 4, 255, 0), _IIf(t And 2, 255, 0), _IIf(t And 1, 255, 0))
        Next X
    Next I
    _Dest 0
End Sub
Function ApplySpline! (S As Spline, V As Single)
    ApplySpline! = S.Y(_Clamp(0, V * 256, 255))
End Function

'================ Subroutines & Functions ================

'======== GL ========
Sub DrawSkyBox
    _glBegin _GL_QUADS
    _glVertex3i 0, 272, 0
    _glColor3ub 255, 255, 0
    _glVertex3i 256, 272, 0
    _glColor3ub 255, 255, 0
    _glVertex3i 256, 272, 256
    _glColor3ub 255, 255, 0
    _glVertex3i 0, 272, 256
    _glColor3ub 255, 255, 0
    _glEnd
End Sub

'$Include:'lib/gl_generateTexture.bm'

Function glVec4%& (X!, Y!, Z!, W!)
    Vec4(0) = X!: Vec4(1) = Y!: Vec4(2) = Z!: Vec4(3) = W!
    glVec4%& = _Offset(Vec4())
End Function

'======== Text ========
Sub gl_DrawLoadingMenuText (Text$)
    Cls , _RGB32(0, 143, 0)
    _Font LargeFont
    _PrintString ((ScreenWidth - _PrintWidth("QB Blocks")) / 2, (ScreenHeight - _FontHeight) / 2), "QB Blocks"
    _Font Font
    _PrintString ((ScreenWidth - _PrintWidth(Text$)) / 2, (ScreenHeight + 4 * _FontHeight) / 2), Text$
    _Display
End Sub
Sub PrintDebug (X As Integer, Y As Integer, Text$)
    _Font SmallFont
    _PrintString (X, Y), Text$
    _Font Font
End Sub

'======== Assets ========
Function LoadAsset& (File$)
    ValidFolders$ = ListStringFromString("assets/blocks/,assets/flowers/")
    For I = 1 To ListStringLength(ValidFolders$)
        If _FileExists(ListStringGet(ValidFolders$, I) + File$ + ".png") = 0 Then _Continue
        LoadAsset& = _LoadImage(ListStringGet(ValidFolders$, I) + File$ + ".png", 32)
        Exit Function
    Next I
    WriteLog "Cannot Load: " + File$
End Function
Function RemoveDoubleQuotes$ (__S$) ' used by AssetsParser.bas
    If Asc(__S$, 1) = 34 And Asc(__S$, Len(__S$)) = 34 Then
        RemoveDoubleQuotes$ = Mid$(__S$, 2, Len(__S$) - 2)
    Else
        RemoveDoubleQuotes$ = __S$
    End If
End Function

'======== Block Hash Table ========
'$Include:'bi/BlockHashTable.bm'

'======== Clouds ========
'$Include:'bi/Clouds.bm'

'======== Log ========
Sub WriteLog (msg$) Static
    _Echo msg$
    Print #100, msg$
End Sub
Sub FileLog (msg$) Static
    Print #100, msg$
End Sub

'======== Game Files ========
Sub ReadSettings
    Open "saves/gamesettings.dat" For Binary As #99
    Get #99, , GameSettings
    Close #99
End Sub
Sub WriteSettings
    Open "saves/gamesettings.dat" For Binary As #99
    Put #99, , GameSettings
    Close #99
End Sub

'======== External Libraries ========
'$Include:'lib/hex.bm'
'$Include:'lib/tokenizer.bm'
'$Include:'lib/perlin/perlin.bm'
'$Include:'lib/clampcycle.bm'
'$Include:'lib/inrange.bm'
'$Include:'lib/modfloor.bm'
'$Include:'lib/LongBuffer.bm'
'$Include:'lib/interpolate.bm'
