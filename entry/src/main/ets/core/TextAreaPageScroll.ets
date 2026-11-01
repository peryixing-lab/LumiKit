/** Idle editors yield vertical drags to their page; active editors retain native text gestures. */
export class TextAreaPageScroll implements AttributeModifier<TextAreaAttribute> {
  private editing: boolean = false;

  applyNormalAttribute(input: TextAreaAttribute): void {
    input.onEditChange((editing: boolean): void => { this.editing = editing; });
    input.onGestureJudgeBegin((info: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
      if (!this.editing && info.isSystemGesture &&
        info.type === GestureControl.GestureType.PAN_GESTURE) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    });
  }
}
