using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.EventSystems;

/// <summary>Creates two minimal sample scenes without overwriting existing consumer scenes.</summary>
public static class CreateRinseRevealScenes
{
    [MenuItem("Tools/IssueCapture/Create sample Boardwalk and Clean")]
    private static void Create()
    {
        const string folder = "Assets/IssueCaptureExampleScenes";
        if (AssetDatabase.IsValidFolder(folder))
            throw new System.InvalidOperationException("Sample folder already exists; nothing was overwritten.");
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        AssetDatabase.CreateFolder("Assets", "IssueCaptureExampleScenes");
        foreach (string name in new[] { "Boardwalk", "Clean" })
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);
            new GameObject("Sample controller").AddComponent<RinseRevealExample>().sceneIdentity = name;
            new GameObject("Event system", typeof(EventSystem), typeof(StandaloneInputModule));
            string path = folder + "/" + name + ".unity";
            EditorSceneManager.SaveScene(scene, path);
            EditorBuildSettings.scenes = EditorBuildSettings.scenes.Concat(new[] { new EditorBuildSettingsScene(path, true) }).ToArray();
        }
        EditorSceneManager.OpenScene(folder + "/Boardwalk.unity", OpenSceneMode.Single);
    }
}
