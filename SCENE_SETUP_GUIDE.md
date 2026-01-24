# Player Scene Manual Modifications Guide

Since automated scene file modification isn't available, please follow these steps to complete the gun integration:

## Step 1: Add Gun to Player Scene

1. Open `Scenes/player.tscn` in Godot Editor
2. In the Scene tree, navigate to: `Player` → `CharacterBody3D` → `Skeleton3D` → `arm-right`
3. Right-click on `arm-right` and select "Add Child Node"
4. Add a `Marker3D` node and name it `GunAttachPoint`
5. In the Inspector, set the Transform Position to `(0, -0.2, 0)`
6. Right-click on `GunAttachPoint` and select "Instantiate Child Scene"
7. Select `Scenes/gun.tscn`
8. Save the scene

## Step 2: Add AnimationTree to Player

1. In the same `player.tscn` scene
2. Navigate to: `Player` → `CharacterBody3D`
3. Right-click on `CharacterBody3D` and select "Add Child Node"
4. Add an `AnimationTree` node
5. In the Inspector for AnimationTree:
   - Set "Anim Player" to `../AnimationPlayer`
   - Click on "Tree Root" and select "New AnimationNodeBlendTree"
6. Click the edit button next to Tree Root to open the blend tree editor

## Step 3: Setup Animation Blend Tree

In the AnimationTree blend tree editor:

1. **Add Movement State Machine:**
   - Right-click in the graph → Add Node → AnimationNodeStateMachine
   - Name it "movement"
   - Double-click to edit it
   - Add three AnimationNodeAnimation nodes:
     - "idle" (set animation to "idle")
     - "walk" (set animation to "walk")  
     - "sprint" (set animation to "sprint")
   - Connect them with transitions
   - Connect to the output

2. **Add Gun Holding Blend:**
   - Go back to the main blend tree
   - Add an AnimationNodeBlend2 node and name it "gun_mode"
   - Connect "movement" to input 0
   - Add an AnimationNodeAnimation for "holding-right" and connect to input 1
   - Connect "gun_mode" output to the final output

3. **Save the scene**

## Alternative: Simplified Approach (Recommended for Testing)

If the AnimationTree setup is too complex, you can test the gun mechanics without it:

1. Just complete Step 1 (Add Gun to Player Scene)
2. The player script will fall back to using AnimationPlayer
3. Gun shooting and switching will work, but you won't have animation blending

The gun will still:
- Shoot bullets from the muzzle
- Show muzzle flash
- Toggle on/off with E key
- Fire with the shoot button

You can add the AnimationTree later for the blended animations.

## Testing

After completing Step 1 (minimum):
1. Press F5 to run the game
2. Press E to equip/unequip the gun
3. Press the shoot button to fire
4. Check console for "Gun equipped: true/false" messages
