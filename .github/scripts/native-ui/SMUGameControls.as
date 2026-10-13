package {
 import flash.display.DisplayObject;
 import flash.display.DisplayObjectContainer;
 import flash.display.MovieClip;
 import flash.display.Sprite;
 import flash.events.Event;
 import flash.events.MouseEvent;
 import flash.geom.Point;
 import flash.text.TextField;
 import flash.text.TextFormat;
 import flash.utils.Dictionary;
 [SWF(width="640",height="960",frameRate="24")]
 public final class SMUGameControls extends Sprite {
  private var owner:Object;
  private var panel:Sprite;
  private var track:Sprite;
  private var thumb:Sprite;
  private var title:TextField;
  private var pending:Number=0;
  private var degrees:Number=60;
  private var topFraction:Number=0;
  private var bottomFraction:Number=0;
  private var available:Boolean=true;
  private var dragging:Boolean=false;
  private var shifted:Dictionary=new Dictionary(true);
  public function SMUGameControls() {
   mouseEnabled=false;mouseChildren=false;
   if(parent) install(); else addEventListener(Event.ADDED,install);
  }
  private function install(e:Event=null):void {
   if(!parent || owner) return;
   removeEventListener(Event.ADDED,install);owner=parent;
   owner["SMU_Tick"]=tick;owner["SMU_DrainFOV"]=drain;
   addEventListener(Event.ENTER_FRAME,layout);
  }
  public function tick(value:Number,top:Number,bottom:Number,enabled:Number):Number {
   if(!dragging) degrees=Math.max(45,Math.min(100,Math.round(value)));
   topFraction=Math.max(0,Math.min(0.15,top));bottomFraction=Math.max(0,Math.min(0.15,bottom));available=enabled!=0;
   layout();return 9;
  }
  public function drain():Number {var value:Number=pending;pending=0;return value;}
  private function portHeight():Number {
   var doc:Object=DisplayObject(owner).root;
   return doc && doc.hasOwnProperty("m_PortHeight") ? Number(doc.m_PortHeight) : (stage ? stage.stageHeight : 960);
  }
  private function portWidth():Number {
   var doc:Object=DisplayObject(owner).root;
   return doc && doc.hasOwnProperty("m_PortWidth") ? Number(doc.m_PortWidth) : (stage ? stage.stageWidth : 640);
  }
  private function shift(clip:DisplayObject,offset:Number):void {
   if(!clip || !clip.parent) return;
   var state:Object=shifted[clip];
   if(!state) {state={base:clip.y,last:NaN};shifted[clip]=state;}
   if(isNaN(state.last) || Math.abs(clip.y-state.last)>0.1) state.base=clip.y;
   var parentClip:DisplayObject=clip.parent;
   var a:Point=parentClip.globalToLocal(new Point(0,0));var b:Point=parentClip.globalToLocal(new Point(0,offset));
   clip.y=state.base+b.y-a.y;state.last=clip.y;
  }
  private function layout(e:Event=null):void {
   if(!owner || !stage) return;
   var h:Number=portHeight();var w:Number=portWidth();var top:Number=h*topFraction;
   shift(owner.mvc_TopLeft as DisplayObject,top);shift(owner.mvc_TopRight as DisplayObject,top);
   shift(owner.mvc_MainObjectives as DisplayObject,top);shift(owner.mvc_PowerUpTimer as DisplayObject,top);
   shift(owner.mvc_BossMeter_Anim as DisplayObject,top);shift(owner.mvc_IntroBanner as DisplayObject,top);
   if(owner.btn_Pause is DisplayObject && DisplayObject(owner.btn_Pause).parent==owner) shift(owner.btn_Pause as DisplayObject,top);
   var pause:DisplayObjectContainer=owner.mvc_Pause as DisplayObjectContainer;
   if(!pause || !pause.visible || !DisplayObject(owner).visible) {
    if(panel) panel.visible=false;
    if(dragging) endDrag(null);
    return;
   }
   if(!panel) build();
   if(panel.parent!=pause) pause.addChild(panel);
   // Place this native child below the authored pause controls. Transform only this
   // child; retain the game's pause artwork, buttons, objectives and touch mapping.
   var scale:Number=Math.min(w/640,h/960);
   var origin:Point=pause.globalToLocal(new Point((w-584*scale)/2,h*(1-bottomFraction)-158*scale));
   var unit:Point=pause.globalToLocal(new Point((w-584*scale)/2+scale,h*(1-bottomFraction)-158*scale));
   panel.x=origin.x;panel.y=origin.y;panel.scaleX=panel.scaleY=unit.x-origin.x;
   panel.visible=true;panel.mouseEnabled=available;panel.mouseChildren=available;panel.alpha=available ? 1 : 0.55;
   pause.setChildIndex(panel,pause.numChildren-1);
   update();
  }
  private function text(label:String,x:Number,y:Number,width:Number,size:Number,color:uint):TextField {
   var t:TextField=new TextField();t.x=x;t.y=y;t.width=width;t.height=38;t.selectable=false;t.mouseEnabled=false;
   t.embedFonts=true;t.defaultTextFormat=new TextFormat("Komika Title - Paint",size,color,true);t.text=label;return t;
  }
  private function build():void {
   panel=new Sprite();panel.name="SMU_FOV_Panel";
   panel.graphics.lineStyle(4,0x111111);panel.graphics.beginFill(0xffffff);panel.graphics.drawRect(0,0,584,132);panel.graphics.endFill();
   panel.graphics.lineStyle();panel.graphics.beginFill(0xe91b23);panel.graphics.drawRect(2,2,580,40);panel.graphics.endFill();
   title=text("FIELD OF VIEW  60",14,7,424,25,0xffffff);panel.addChild(title);
   var reset:Sprite=new Sprite();reset.graphics.beginFill(0x111111);reset.graphics.drawRect(460,5,116,32);reset.graphics.endFill();reset.buttonMode=true;
   reset.addChild(text("RESET",475,5,98,23,0xffffff));reset.addEventListener(MouseEvent.CLICK,onReset);panel.addChild(reset);
   track=new Sprite();track.x=28;track.y=87;track.buttonMode=true;
   track.graphics.beginFill(0,0);track.graphics.drawRect(-15,-30,558,60);track.graphics.endFill();
   track.graphics.beginFill(0x252525);track.graphics.drawRect(0,-5,528,10);track.graphics.endFill();
   track.addEventListener(MouseEvent.MOUSE_DOWN,startDragFOV);panel.addChild(track);
   thumb=new Sprite();thumb.graphics.lineStyle(3,0x111111);thumb.graphics.beginFill(0xffd126);thumb.graphics.drawCircle(0,0,18);thumb.graphics.endFill();thumb.mouseEnabled=false;track.addChild(thumb);
   panel.addChild(text("45",23,103,80,19,0x111111));panel.addChild(text("100",518,103,60,19,0x111111));
  }
  private function update():void {if(title) {title.text="FIELD OF VIEW  "+int(degrees);thumb.x=(degrees-45)/55*528;}}
  private function startDragFOV(e:MouseEvent):void {
   if(!available || !stage) return;
   e.stopImmediatePropagation();dragging=true;
   stage.addEventListener(MouseEvent.MOUSE_MOVE,moveDrag);stage.addEventListener(MouseEvent.MOUSE_UP,endDrag);stage.addEventListener(Event.MOUSE_LEAVE,endDrag);
   moveDrag(e);
  }
  private function moveDrag(e:MouseEvent):void {
   if(!dragging) return;
   if(e) e.stopImmediatePropagation();
   var p:Point=track.globalToLocal(new Point(e.stageX,e.stageY));
   degrees=Math.max(45,Math.min(100,Math.round(45+p.x/528*55)));pending=degrees;update();
  }
  private function endDrag(e:Event):void {
   if(e) e.stopImmediatePropagation();
   dragging=false;
   if(stage) {stage.removeEventListener(MouseEvent.MOUSE_MOVE,moveDrag);stage.removeEventListener(MouseEvent.MOUSE_UP,endDrag);stage.removeEventListener(Event.MOUSE_LEAVE,endDrag);}
  }
  private function onReset(e:MouseEvent):void {e.stopImmediatePropagation();degrees=60;pending=60;update();}
 }
}
