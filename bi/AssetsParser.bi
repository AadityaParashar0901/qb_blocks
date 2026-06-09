Type TextureData
    As String Name
    As Long Handle
    As _Unsigned _Byte AnimationFrames
    As Single X, Y
End Type
Type BlockData
    As String Name, ModelName
    As _Unsigned _Byte Faces(0 To 5)
    As _Unsigned _Byte Transparent, ModelId
End Type
Type Model
    As String Name
    As Vec3_Float Vertices(0 To 255)
    As Vec2_Float TextureCoords(0 To 255)
    As _Unsigned _Byte Count
End Type

Dim Shared As Long TextureAtlas
Dim Shared As _Unsigned Integer TextureSize, TotalTextures, TotalBlocks

Dim Shared As String BlockHashTable_List(0 To 255)
Dim Shared As _Unsigned Integer BlockHashTable_Length(0 To 255)
Dim Shared As String BlockHashTable_Code(0 To 255)

FileContents$ = Tokenizer$(_ReadFile$("assets/assets.list"))
CurrentMode = 0
For I = 1 To ListStringLength(FileContents$)
    CurrentListElement$ = ListStringGet(FileContents$, I)
    Select Case CurrentMode
        Case 0: Select Case CurrentListElement$
                Case "texture_size": I = I + 2
                    TextureSize = Val(ListStringGet(FileContents$, I))
                    FileLog "Texture Size:" + Str$(TextureSize)
                Case "textures": CurrentMode = 1: I = I + 1
                    ReDim Shared Textures(0) As TextureData
                    CurrentTextureID = 0: TextureMode = 0
                    Y~% = 0
                Case "blocks": CurrentMode = 2: I = I + 1
                    ReDim Shared Blocks(0) As BlockData
                    ReDim Shared isTransparent(0) As _Unsigned _Bit
                    ReDim Shared omitBlockFace(0) As _Unsigned _Byte
                    isTransparent(0) = 1
                    omitBlockFace(0) = 63
                    CurrentBlockID = 0: BlockMode = 0
                Case "models": CurrentMode = 3: I = I + 1
                    ReDim Shared CustomModels(0) As Model
                Case ";"
            End Select
        Case 1
            Select Case CurrentListElement$
                Case ";": TextureMode = 0
                Case "}": If TextureMode = 0 Then CurrentMode = 0
                Case ","
                Case "animate": I = I + 2: Textures(CurrentTextureID).AnimationFrames = Val(ListStringGet(FileContents$, I)) ' not being used currently
                Case Else: FileLog "Loading Texture(" + ByteToHex$(CurrentTextureID) + "): " + CurrentListElement$
                    If TextureMode Then _Continue
                    CurrentTextureID = CurrentTextureID + 1: TextureMode = 1
                    ReDim _Preserve Shared Textures(1 To CurrentTextureID) As TextureData
                    Textures(CurrentTextureID).Handle = LoadAsset(CurrentListElement$)
                    Textures(CurrentTextureID).Name = CurrentListElement$
                    TextureMode = 1
            End Select

        Case 2
            Select Case CurrentListElement$
                Case ";": BlockMode = 0
                Case "}": If BlockMode = 0 Then CurrentMode = 0
                Case "name": I = I + 2
                    CurrentBlockID = CurrentBlockID + 1
                    ReDim _Preserve Shared Blocks(1 To CurrentBlockID) As BlockData
                    ReDim _Preserve Shared isTransparent(0 To CurrentBlockID) As _Unsigned _Bit
                    ReDim _Preserve Shared omitBlockFace(0 To CurrentBlockID) As _Unsigned _Byte
                    Blocks(CurrentBlockID).Name = RemoveDoubleQuotes$(ListStringGet(FileContents$, I))
                    BlockMode = 1
                    FileLog "Block Name(" + ByteToHex$(CurrentBlockID) + "): " + Blocks(CurrentBlockID).Name
                Case "textures": If BlockMode = 0 Then _Continue
                    I = I + 2
                    Select Case ListStringGet(FileContents$, I)
                        Case "[": For J = 1 To 6
                                Blocks(CurrentBlockID).Faces(J - 1) = Val(ListStringGet(FileContents$, I + J * 2 - 1))
                            Next J
                            I = I + 11
                        Case Else
                            For J = 0 To 5: Blocks(CurrentBlockID).Faces(J) = Val(ListStringGet(FileContents$, I)): Next J
                    End Select
                    FileLog "Block Textures: " + Str$(Blocks(CurrentBlockID).Faces(0)) + Str$(Blocks(CurrentBlockID).Faces(1)) + Str$(Blocks(CurrentBlockID).Faces(2)) + Str$(Blocks(CurrentBlockID).Faces(3)) + Str$(Blocks(CurrentBlockID).Faces(4)) + Str$(Blocks(CurrentBlockID).Faces(5))
                Case "transparent": If BlockMode = 0 Then _Continue
                    Blocks(CurrentBlockID).Transparent = -1
                    isTransparent(CurrentBlockID) = 1
                    FileLog "Block is transparent"
                Case "omit": If BlockMode = 0 Then _Continue
                    Select Case ListStringGet(FileContents$, I + 2)
                        Case "[": I = I + 2: For J = 0 To 5
                                If Val(ListStringGet(FileContents$, I + J * 2 + 1)) Then omitBlockFace(CurrentBlockID) = _SetBit(omitBlockFace(CurrentBlockID), J)
                            Next J
                            I = I + 11
                        Case Else
                            omitBlockFace(CurrentBlockID) = 63
                    End Select
                    FileLog "Omit Block Face: " + _ToStr$(omitBlockFace(CurrentBlockID))
                Case "model": I = I + 2
                    Blocks(CurrentBlockID).ModelName = RemoveDoubleQuotes$(ListStringGet(FileContents$, I))
                    For J = 1 To UBound(CustomModels)
                        If Blocks(CurrentBlockID).ModelName <> CustomModels(J).Name Then _Continue
                        Blocks(CurrentBlockID).ModelId = J
                        Exit For
                    Next J
                    If Blocks(CurrentBlockID).ModelId = 0 Then WriteLog "Error: Model '" + Blocks(CurrentBlockID).ModelName + "' not found!"
            End Select

        Case 3
            Select Case CurrentListElement$
                Case ";": ModelMode = 0
                Case "name": I = I + 2
                    CurrentModelID = CurrentModelID + _IIf(ModelMode, 0, 1)
                    CustomModelVertexId = _IIf(ModelMode, CustomModelVertexId, 0)
                    ReDim _Preserve Shared CustomModels(1 To CurrentModelID) As Model
                    CustomModels(CurrentModelID).Name = RemoveDoubleQuotes$(ListStringGet(FileContents$, I))
                    ModelMode = 1
                    FileLog "Model: " + CustomModels(CurrentModelID).Name
                Case "vertices": I = I + 2
                    CustomModels(CurrentModelID).Count = Val(RemoveDoubleQuotes$(ListStringGet(FileContents$, I)))
                    ModelMode = 2
                    FileLog "    Vertices: " + _ToStr$(CustomModels(CurrentModelID).Count)
                Case "data": I = I + 2
                    Do
                        Select Case ListStringGet(FileContents$, I)
                            Case "[": ModelVertexMode = 0
                            Case "]": FileLog "    Vertex[" + _ToStr$(CustomModelVertexId) + "]: " + _ToStr$(CustomModels(CurrentModelID).Vertices(CustomModelVertexId).X) + ", " + _ToStr$(CustomModels(CurrentModelID).Vertices(CustomModelVertexId).Y) + ", " + _ToStr$(CustomModels(CurrentModelID).Vertices(CustomModelVertexId).Z) + ", " + _ToStr$(CustomModels(CurrentModelID).TextureCoords(CustomModelVertexId).X) + ", " + _ToStr$(CustomModels(CurrentModelID).TextureCoords(CustomModelVertexId).Y)
                                CustomModelVertexId = CustomModelVertexId + 1
                            Case "{"
                            Case "}": Exit Do
                            Case ","
                            Case Else: ModelVertexMode = ModelVertexMode + 1
                                V = Val(ListStringGet(FileContents$, I))
                                Select Case ModelVertexMode
                                    Case 1: CustomModels(CurrentModelID).Vertices(CustomModelVertexId).X = V
                                    Case 2: CustomModels(CurrentModelID).Vertices(CustomModelVertexId).Y = V
                                    Case 3: CustomModels(CurrentModelID).Vertices(CustomModelVertexId).Z = V
                                    Case 4: CustomModels(CurrentModelID).TextureCoords(CustomModelVertexId).X = V
                                    Case 5: CustomModels(CurrentModelID).TextureCoords(CustomModelVertexId).Y = V
                                End Select
                        End Select
                        I = I + 1
                    Loop
                Case "}": CurrentMode = 0
                Case ","
            End Select
    End Select
Next I
TotalTextures = UBound(Textures): FileLog "Total Textures: " + _ToStr$(TotalTextures)
TotalBlocks = UBound(Blocks): FileLog "Total Blocks: " + _ToStr$(TotalBlocks)
'======== Build Hash Table ========
For I = 1 To TotalBlocks
    Hash~%% = getHash~%%(Blocks(I).Name)
    If BlockHashTable_Length(Hash~%%) = 0 Then BlockHashTable_List(Hash~%%) = ListStringNew$
    ListStringAdd BlockHashTable_List(Hash~%%), Blocks(I).Name
    BlockHashTable_Length(Hash~%%) = BlockHashTable_Length(Hash~%%) + 1
    BlockHashTable_Code(Hash~%%) = BlockHashTable_Code(Hash~%%) + MKI$(I)
    FileLog "isTransparent(" + Blocks(I).Name + "): " + _IIf(isTransparent(I), "True", "False")
Next I
For I = 0 To 255
    If BlockHashTable_List(I) = "" Then _Continue
    FileLog "Block Hash Table (" + ByteToHex$(I) + "): " + ListStringPrint(BlockHashTable_List(I))
Next I
'======== Create Texture Atlas ========
Dim Shared TextureAtlasSize As _Unsigned Long
TextureAtlasSize = _Ceil(Sqr(TotalTextures))
X = 0: Y = 0
TextureAtlas = _NewImage(TextureAtlasSize * TextureSize, TextureAtlasSize * TextureSize, 32)
For I = 1 To TotalTextures
    _PutImage (X * TextureSize, Y * TextureSize)-((X + 1) * TextureSize - 1, (Y + 1) * TextureSize - 1), Textures(I).Handle, TextureAtlas, (0, 0)-(TextureSize - 1, TextureSize - 1)
    If Textures(I).AnimationFrames = 0 Then _FreeImage Textures(I).Handle
    Textures(I).X = X / TextureAtlasSize
    Textures(I).Y = Y / TextureAtlasSize

    X = X + 1
    If X >= TextureAtlasSize Then
        X = 0
        Y = Y + 1
    End If
Next I
Dim Shared As Single CalculatedTextureSize
CalculatedTextureSize = (TextureSize - 1) / TextureAtlasSize / TextureSize
