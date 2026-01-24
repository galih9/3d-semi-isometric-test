import re

# Read the player.tscn file
with open(r'c:\Users\galih\Documents\Projects\Godot\glb-test\Scenes\player.tscn', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the arm-right MeshInstance3D section and add gun attachment after it
arm_right_mesh_pattern = r'(\[node name="arm-right" type="MeshInstance3D" parent="CharacterBody3D/Skeleton3D/arm-right"\]\nmesh = SubResource\("ArrayMesh_0mbce"\)\nskeleton = NodePath\(""\))'

gun_attachment = r'''\1

[node name="GunAttachPoint" type="Marker3D" parent="CharacterBody3D/Skeleton3D/arm-right"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.2, 0)

[node name="Gun" parent="CharacterBody3D/Skeleton3D/arm-right/GunAttachPoint" instance=ExtResource("2_6t5aa")]'''

content = re.sub(arm_right_mesh_pattern, gun_attachment, content)

# Find the AnimationPlayer section and add AnimationTree after it
anim_player_pattern = r'(\[node name="AnimationPlayer" type="AnimationPlayer" parent="CharacterBody3D"\]\nlibraries = \{\n&"": SubResource\("AnimationLibrary_eo808"\)\n\})'

anim_tree = r'''\1

[node name="AnimationTree" type="AnimationTree" parent="CharacterBody3D"]
anim_player = NodePath("../AnimationPlayer")'''

content = re.sub(anim_player_pattern, anim_tree, content)

# Write the modified content back
with open(r'c:\Users\galih\Documents\Projects\Godot\glb-test\Scenes\player.tscn', 'w', encoding='utf-8') as f:
    f.write(content)

print("Player scene modified successfully!")
