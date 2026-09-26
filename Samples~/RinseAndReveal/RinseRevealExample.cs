using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using VinWare.IssueCapture;
using Capture = VinWare.IssueCapture.IssueCapture;

/// <summary>Small standalone uGUI example; copy the instrumentation patterns into existing game handlers.</summary>
public sealed class RinseRevealExample : MonoBehaviour
{
    /// <summary>Explicit source scene identity assigned by the sample scene generator.</summary>
    public string sceneIdentity = "Boardwalk";
    private IssueScreen scene;
    private IssueScreen play;
    private IssueScreen inventory;
    private IssueScreen overlay;
    private bool inventorySelected;
    private GameObject overlayPanel;

    private void Start()
    {
        // The sample works in the editor/production too; capture calls become no-ops there.
        Capture.Initialize("rinse-and-reveal");
        scene = Capture.RegisterScreen("scene." + sceneIdentity.ToLowerInvariant(), sceneIdentity,
            "RinseRevealExample");
        play = Capture.RegisterScreen("surface.play", "Play", "RinseRevealExample.Play", scene);
        inventory = Capture.RegisterScreen("surface.inventory", "Inventory", "RinseRevealExample.Inventory",
            scene, active: false);
        BuildControls();
    }

    private void BuildControls()
    {
        var canvasObject = new GameObject("Example canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        canvasObject.GetComponent<Canvas>().renderMode = RenderMode.ScreenSpaceOverlay;
        var scaler = canvasObject.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(800, 1000);
        var panel = CreatePanel(canvasObject.transform, "Scene controls");
        AddButton(panel.transform, sceneIdentity + ": change scene", Navigate);
        AddButton(panel.transform, "Toggle retained play / inventory", ToggleInventory);
        AddButton(panel.transform, "Open pause overlay", ShowOverlay);
        AddButton(panel.transform, "Start async clean outcome", BeginClean);
        if (Capture.IsEnabled)
        {
            AddButton(panel.transform, "Report issue", Capture.Capture);
            AddButton(panel.transform, "Saved issues / export", Capture.OpenInbox);
            AddButton(panel.transform, "Context diagnostics", Capture.OpenDiagnostics);
        }
        overlayPanel = CreatePanel(canvasObject.transform, "Pause overlay");
        AddButton(overlayPanel.transform, "Close pause overlay", HideOverlay);
        overlayPanel.SetActive(false);
    }

    private IssueScreen CurrentSurface => inventorySelected ? inventory : play;

    private void Navigate()
    {
        CurrentSurface.Reporter.Navigation(sceneIdentity == "Boardwalk" ? "boardwalk.enter_clean" : "clean.return_boardwalk");
        SceneManager.LoadScene(sceneIdentity == "Boardwalk" ? "Clean" : "Boardwalk");
    }

    private void ToggleInventory()
    {
        if (overlay != null) return;
        CurrentSurface.Reporter.Action("inventory.toggle");
        inventorySelected = !inventorySelected;
        play.SetActive(!inventorySelected);
        inventory.SetActive(inventorySelected);
    }

    private void ShowOverlay()
    {
        if (overlay != null) return;
        CurrentSurface.Reporter.Action("pause.open");
        overlay = Capture.RegisterScreen("overlay.pause", "Pause", "RinseRevealExample.Pause", CurrentSurface);
        overlayPanel.SetActive(true);
    }

    private void HideOverlay()
    {
        overlay?.Reporter.Action("pause.close");
        overlay?.Dispose();
        overlay = null;
        overlayPanel.SetActive(false);
    }

    private async void BeginClean()
    {
        var origin = CurrentSurface.Reporter;
        origin.Action("clean.begin");
        // Stand-in for the game's existing operation. Navigate away during this delay.
        await Task.Delay(1500);
        origin.Outcome("clean.complete", IssueOutcome.Success);
    }

    private void OnDestroy()
    {
        overlay?.Dispose();
        inventory?.Dispose();
        play?.Dispose();
        scene?.Dispose();
    }

    private static GameObject CreatePanel(Transform parent, string name)
    {
        var panel = new GameObject(name, typeof(RectTransform), typeof(Image), typeof(VerticalLayoutGroup));
        panel.transform.SetParent(parent, false);
        var rect = (RectTransform)panel.transform;
        rect.anchorMin = new Vector2(0.1f, 0.15f);
        rect.anchorMax = new Vector2(0.9f, 0.85f);
        rect.offsetMin = rect.offsetMax = Vector2.zero;
        panel.GetComponent<Image>().color = new Color(0.08f, 0.18f, 0.22f, 0.98f);
        panel.GetComponent<VerticalLayoutGroup>().spacing = 12;
        return panel;
    }

    private static void AddButton(Transform parent, string title, UnityEngine.Events.UnityAction action)
    {
        var button = new GameObject(title, typeof(RectTransform), typeof(Image), typeof(Button));
        button.transform.SetParent(parent, false);
        button.GetComponent<Button>().onClick.AddListener(action);
        var label = new GameObject("Label", typeof(RectTransform), typeof(Text));
        label.transform.SetParent(button.transform, false);
        var rect = (RectTransform)label.transform;
        rect.anchorMin = Vector2.zero;
        rect.anchorMax = Vector2.one;
        rect.offsetMin = rect.offsetMax = Vector2.zero;
        var text = label.GetComponent<Text>();
        text.text = title;
        text.font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        text.fontSize = 24;
        text.color = Color.black;
        text.alignment = TextAnchor.MiddleCenter;
    }
}
