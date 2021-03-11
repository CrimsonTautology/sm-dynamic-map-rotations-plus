#include <sourcemod>
#include <testsuite>

#include "../dmr/keyvalues.sp"
#include "../dmr/maphistory.sp"
#include "../dmr/mapgroups.sp"
#include "../dmr/rotation.sp"
#include "../dmr/utils.sp"

char dmr_rotation_raw[] = ""
... "rotation\n"
... "{\n"
... "    // comment\n"
... "    start node_a\n"
... "    node_a\n"
... "    {\n"
... "        map cp_map_a1\n"
... "        default_nextnode node_b\n"
... "        command \"echo --- DMR TestSuite --- RunNodeCommand works\"\n"
... "        pre_command \"echo --- DMR TestSuite --- RunNodePreCommand works\"\n"
... "        title \"The Title\"\n"
... "        test_key test_value\n"
... "        // test_commented_out test_value\n"
... "    }\n"
... "\n"
... "    node_c\n"
... "    {\n"
... "        group single\n"
... "        default_nextnode node_d\n"
... "        node_a {}\n"
... "    }\n"
... "\n"
... "    node_b\n"
... "    {\n"
... "        map tp_map_b2\n"
... "        default_nextnode node_c\n"
... "    }\n"
... "\n"
... "    node_d\n"
... "    {\n"
... "        map never_played\n"
... "        default_nextnode node_d\n"
... "    }\n"
... "}\n";

char dmr_map_groups_raw[] = ""
... "map_groups\n"
... "{\n"
... "    // comment\n"
... "    stock\n"
... "    {\n"
... "        cp_map_1 {}\n"
... "        cp_map_2 {}\n"
... "        cp_map_3 {}\n"
... "        //cp_map_4 {}\n"
... "    }\n"
... "    \n"
... "    custom\n"
... "    {\n"
... "        cp_custom_a1 {}\n"
... "        cp_custom_b2 {}\n"
... "    }\n"
... "\n"
... "    single\n"
... "    {\n"
... "        pl_single{}\n"
... "    }\n"
... "    empty\n"
... "    {\n"
... "    }\n"
... "}\n"

void test_dmr_rotation()
{
    char node[MAX_KEY_LENGTH], val[MAX_KEY_LENGTH];
    bool exists;

    // load up the default dmr_rotation file
    Rotation rotation = new Rotation("testsuite");
    rotation.ImportFromString(dmr_rotation_raw);

    // expect a default start node
    exists = rotation.GetStartNode(node, sizeof(node));
    Test_AssertTrue("start node exists", exists);
    Test_AssertStringsEqual("GetStartNode is node_a", "node_a", node)

    // expect that we can iterate on default_node
    rotation.GetNextNode("node_a", node, sizeof(node));
    Test_AssertStringsEqual("GetNextNode node_a -> node_b",  "node_b", node);

    rotation.GetNextNode("node_b", node, sizeof(node));
    Test_AssertStringsEqual("GetNextNode node_b -> node_c", "node_c", node);

    rotation.GetNextNode("node_c", node, sizeof(node));
    Test_AssertStringsEqual("GetNextNode node_c -> node_a", "node_a", node);

    rotation.GetNextNode("node_d", node, sizeof(node));
    Test_AssertStringsEqual("GetNextNode node_d -> node_d", "node_d", node);

    // expect that we can retrieve values of specific keys of a given node
    exists = rotation.GetValueOfKeyOfNode("node_a", "test_key", val, sizeof(val));
    Test_AssertTrue("test_key exists", exists);
    Test_AssertStringsEqual("GetValueOfKeyOfNode test_value", "test_value", val);

    exists = rotation.GetValueOfKeyOfNode("node_a", "test_commented_out", val, sizeof(val));
    Test_AssertFalse("does not read commented out keys", exists);

    exists = rotation.GetValueOfKeyOfNode("node_a", "fake_key", val, sizeof(val));
    Test_AssertFalse("fake_key does not exist", exists);

    // expect that we can excute server commands
    Test_Print("Testing RunNodeCommand");
    rotation.RunNodeCommand("node_a");

    Test_Print("Testing RunNodePreCommand");
    rotation.RunNodePreCommand("node_a");

    exists = rotation.RunNodeCommand("node_a", "fake_key");
    Test_AssertFalse("fake_command does not exist", exists);

    // expect that we can get the title of a node if it exists
    rotation.GetTitle("node_a", val, sizeof(val));
    Test_AssertStringsEqual("GetTitle \"The Title\"", "The Title", val);

    // expect that we can get the map of a node (without a map groups structure)
    rotation.GetMap("node_a", val, sizeof(val));
    Test_AssertStringsEqual("GetMap cp_map_a1", "cp_map_a1", val);

    delete rotation;
}

void test_dmr_map_groups()
{
    char map[MAX_KEY_LENGTH], map2[MAX_KEY_LENGTH], val[MAX_KEY_LENGTH];

    // load up the default dmr_rotation file
    MapGroups groups = new MapGroups("testsuite");
    groups.ImportFromString(dmr_map_groups_raw);

    // expect you can get a random map from a group
    groups.GetRandomMapFromGroup("single", map, sizeof(map));
    Test_AssertStringsEqual("GetRandomMapFromGroup pl_single", "pl_single", map);

    // expect map to be stored in cache if provided
    StringMap cache = new StringMap();

    groups.GetRandomMapFromGroup("stock", map, sizeof(map), .cache=cache);

    Test_AssertTrue("map in cache", cache.GetString("stock", val, sizeof(val)));
    Test_AssertStringsEqual("map and cached value are the same", map, val);

    // expect same map to be returned again if it exists in cache
    groups.GetRandomMapFromGroup("stock", map2, sizeof(map2), .cache=cache);
    Test_AssertStringsEqual("same map is returned if in cache", map, map2);

    // expect maps to not be returned if they are recently played
    MapHistory history = new MapHistory();
    history.PushMap("cp_custom_a1", 10);

    groups.GetRandomMapFromGroup("custom", map, sizeof(map), .history=history);
    Test_AssertStringsNotEqual("a previous map is not returned cp_custom_a1", "cp_custom_a1", map);

    // handle empty group

    delete history;
    delete cache;
    delete groups;
}

void test_dmr_integration() {
    char node[MAX_KEY_LENGTH], map[MAX_KEY_LENGTH];

    Rotation rotation = new Rotation("testsuite");
    MapGroups groups = new MapGroups("testsuite");
    StringMap cache = new StringMap();
    MapHistory history = new MapHistory();
    ArrayList items;

    // load data
    rotation.ImportFromString(dmr_rotation_raw);
    groups.ImportFromString(dmr_map_groups_raw);

    // iterate over the rotation
    rotation.GetStartNode(node, sizeof(node));

    rotation.Iterate(node, sizeof(node), map, sizeof(map), groups, cache, history, 10)
    Test_AssertStringsEqual("iterate rotation on node node_b", "node_b", node);
    Test_AssertStringsEqual("iterate rotation on map tp_map_b2", "tp_map_b2", map);

    rotation.Iterate(node, sizeof(node), map, sizeof(map), groups, cache, history, 10)
    Test_AssertStringsEqual("iterate rotation on node node_c", "node_c", node);
    Test_AssertStringsEqual("iterate rotation on map pl_single", "pl_single", map);

    rotation.Iterate(node, sizeof(node), map, sizeof(map), groups, cache, history, 10)
    Test_AssertStringsEqual("iterate rotation on node node_a", "node_a", node);
    Test_AssertStringsEqual("iterate rotation on map cp_map_a1", "cp_map_a1", map);

    // expect history to be updated
    Test_AssertEqual("iteration updated history 3", history.Length, 3);

    // test a dry run iteration that will not update history
    rotation.Iterate(node, sizeof(node), map, sizeof(map), groups)
    Test_AssertStringsEqual("dry iterate rotation on node node_b", "node_b", node);
    Test_AssertStringsEqual("dry iterate rotation on map tp_map_b2", "tp_map_b2", map);
    Test_AssertEqual("dry iteration did not update history 3", 3, history.Length);

    // test GetNextItems as maps
    items = rotation.GetNextItems("node_a", 10, groups, cache);
    Test_AssertEqual("nextnodes has ten items", 10, items.Length);
    Test_AssertEqual("nextmaps 0", 0, items.FindString("tp_map_b2"));
    Test_AssertEqual("nextmaps 1", 1, items.FindString("pl_single"));
    Test_AssertEqual("nextmaps 2", 2, items.FindString("cp_map_a1 (The Title)"));
    Test_AssertEqual("nextmaps 4", 4, items.FindString("single"));
    delete items;

    // test GetNextItems as maps
    items = rotation.GetNextItems("node_a", 7, groups, cache, .as_nodes=true);
    Test_AssertEqual("nextnodes has seven items", 7, items.Length);
    Test_AssertEqual("nextnodes 0", 0, items.FindString("node_b"));
    Test_AssertEqual("nextnodes 1", 1, items.FindString("node_c"));
    Test_AssertEqual("nextnodes 2", 2, items.FindString("node_a (The Title)"));
    delete items;

    // cleanup
    delete history;
    delete cache;
    delete groups;
    delete rotation;
}

public void OnPluginStart()
{
    Test_SetBoxWidth(80);
    Test_StartSection("DMR Data Structures");
    Test_Run("Rotation", test_dmr_rotation);
    Test_Run("MapGroups", test_dmr_map_groups);
    Test_Run("Integration", test_dmr_integration);
    Test_EndSection();
}
