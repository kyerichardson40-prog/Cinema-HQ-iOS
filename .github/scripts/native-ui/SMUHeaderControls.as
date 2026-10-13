package {
 import flash.display.DisplayObject;
 import flash.display.Sprite;
 import flash.events.Event;
 import flash.geom.Point;
 [SWF(width="640",height="960",frameRate="24")]
 public final class SMUHeaderControls extends Sprite {
  private var owner:Object;
  private var topFraction:Number=0;
  private var bar:DisplayObject;
  private var base:Number=0;
  private var last:Number=NaN;
  private var fill:Sprite=new Sprite();
  public function SMUHeaderControls() {
   mouseEnabled=false;mouseChildren=false;fill.mouseEnabled=false;
   if(parent) install();else addEventListener(Event.ADDED,install);
  }
  private function install(e:Event=null):void {
   if(!parent || owner) return;
   removeEventListener(Event.ADDED,install);owner=parent;
   owner["SMU_HeaderInset"]=inset;addEventListener(Event.ENTER_FRAME,layout);
  }
  public function inset(top:Number):Number {topFraction=Math.max(0,Math.min(0.15,top));layout();return 9;}
  private function layout(e:Event=null):void {
   if(!owner || !stage) return;
   var doc:Object=DisplayObject(owner).root;
   var h:Number=doc && doc.hasOwnProperty("m_PortHeight") ? Number(doc.m_PortHeight) : stage.stageHeight;
   var w:Number=doc && doc.hasOwnProperty("m_PortWidth") ? Number(doc.m_PortWidth) : stage.stageWidth;
   var current:DisplayObject=owner.mvc_TopBar as DisplayObject;
   if(!current || !current.parent) return;
   if(bar!=current) {bar=current;base=bar.y;last=NaN;}
   if(isNaN(last) || Math.abs(bar.y-last)>0.1) base=bar.y;
   var a:Point=bar.parent.globalToLocal(new Point(0,0));var b:Point=bar.parent.globalToLocal(new Point(0,h*topFraction));
   bar.y=base+b.y-a.y;last=bar.y;
   // Extend the authored red header behind the Island; only menu artwork is
   // affected. The framebuffer, camera aspect and gameplay viewport stay full-screen.
   if(fill.parent!=bar.parent) bar.parent.addChildAt(fill,0);
   var end:Point=bar.parent.globalToLocal(new Point(w,h*topFraction));
   fill.graphics.clear();fill.graphics.beginFill(0xef181d);fill.graphics.drawRect(a.x,a.y,end.x-a.x,end.y-a.y+2);fill.graphics.endFill();
   fill.visible=bar.visible && topFraction>0;
  }
 }
}
