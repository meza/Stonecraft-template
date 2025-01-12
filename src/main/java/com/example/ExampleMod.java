package com.example;
/*? if fabric {*/
import net.fabricmc.api.ModInitializer;
/*?}*/

/*? if forge {*/
/*import net.minecraftforge.fml.common.Mod;
import net.minecraftforge.fml.javafmlmod.FMLJavaModLoadingContext;
*/
/*?}*/

/*? if neoforge {*/
/*import net.neoforged.fml.ModContainer;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.common.Mod;
*/
/*?}*/

/*? if forgeLike {*/
/*@Mod("examplemod")
public class ExampleMod {*/
/*?}*/

/*? if fabric {*/
public class ExampleMod implements ModInitializer {
/*?}*/

    /*? if forge {*/
    /*public ExampleMod(final FMLJavaModLoadingContext context) {}*/
    /*?}*/

    /*? if neoforge {*/
    /*public ExampleMod(IEventBus modEventBus, ModContainer modContainer) {}*/
    /*?}*/

    /*? if fabric {*/
    @Override
    public void onInitialize() {}
    /*?}*/
}
